//
//  CrashDeliveryTests.swift
//
//  Crash events (`error_context.is_crash`) must survive process death:
//  - hybrid path: they bypass the beforeSend JS round trip and upload directly,
//    since the process is usually dying when a crash is exported
//  - the exporter confirms each crash upload per correlation id (`didConfirmCrashUpload(id:)`),
//    which gates purging the pending PLCrashReporter report on next launch
//  - `CoralogixRum.flush()` force-exports spans still queued in the batch
//    processor instead of waiting out the schedule delay
//

import XCTest
import CoralogixInternal
import Foundation

@testable import Coralogix

final class CrashDeliveryTests: XCTestCase {

    private var coralogixRum: CoralogixRum!

    override func tearDownWithError() throws {
        coralogixRum?.shutdown()
        coralogixRum = nil
    }

    // MARK: - Fixtures

    /// Test-only `SpanUploading` with a configurable result that records every batch.
    private final class StubUploader: SpanUploading {
        var result: SpanExporterResultCode = .success
        private(set) var uploadedBatches: [[[String: Any]]] = []
        private static let serverError = SpanUploadResult(disposition: .retryable, httpStatus: 500, retryAfter: nil, countsAsFailedUpload: true)
        func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
            uploadedBatches.append(spans)
            return result == .success ? .delivered : Self.serverError
        }
        var uploadedEvents: [[String: Any]] { uploadedBatches.flatMap { $0 } }
    }

    /// An error-event `SpanData` that survives the encoding pipeline
    /// (`CxRumBuilder.build()` requires session attributes) and carries the
    /// `is_crash` flag under test.
    private func makeErrorSpan(isCrash: Bool, crashEventId: String = "crash-id") -> SpanData {
        var attributes: [String: AttributeValue] = [
            Keys.eventType.rawValue: AttributeValue(CoralogixEventType.error.rawValue),
            Keys.severity.rawValue: AttributeValue("5"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.environment.rawValue: AttributeValue("test"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
            Keys.errorMessage.rawValue: AttributeValue("crash-delivery-test"),
            Keys.isCrash.rawValue: AttributeValue.bool(isCrash)
        ]
        if isCrash {
            attributes[Keys.crashEventId.rawValue] = AttributeValue(crashEventId)
        }
        return SpanData(traceId: TraceId.random(),
                        spanId: SpanId.random(),
                        name: "errorSpan_isCrash_\(isCrash)",
                        kind: .client,
                        startTime: Date(),
                        attributes: attributes,
                        endTime: Date(),
                        hasEnded: true)
    }

    /// A recovered PLCrashReporter report, shaped the way recovery shapes one: an error event
    /// carrying a `threads` stack and a `crash_event_id`. `sessionSampledIn` mirrors the stamp
    /// `attribute(_:to:)` copies from the crash's record; `nil` leaves it unstamped, which the
    /// exporter treats as sampled in.
    private func makePendingReportSpan(crashEventId: String = "report-id",
                                       sessionSampledIn: Bool? = nil) -> SpanData {
        let threads = Helper.convertArrayOfStringToJsonString(array: [
            Helper.convertArrayToJsonString(array: [["frame_number": "0", "binary": "HostApp"]])
        ])
        var attributes: [String: AttributeValue] = [
            Keys.eventType.rawValue: AttributeValue(CoralogixEventType.error.rawValue),
            Keys.severity.rawValue: AttributeValue("5"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.environment.rawValue: AttributeValue("test"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
            Keys.isCrash.rawValue: AttributeValue.bool(true),
            Keys.exceptionType.rawValue: AttributeValue("SIGSEGV"),
            Keys.threads.rawValue: AttributeValue(threads),
            Keys.crashEventId.rawValue: AttributeValue(crashEventId)
        ]
        if let sessionSampledIn {
            attributes[Keys.spanSessionSampledIn.rawValue] = AttributeValue(String(sessionSampledIn))
        }
        return SpanData(traceId: TraceId.random(),
                        spanId: SpanId.random(),
                        name: "pendingCrashReportSpan",
                        kind: .client,
                        startTime: Date(),
                        attributes: attributes,
                        endTime: Date(),
                        hasEnded: true)
    }

    private func isCrashEvent(_ event: [String: Any]) -> Bool {
        let text = event[Keys.text.rawValue] as? [String: Any]
        let cxRum = text?[Keys.cxRum.rawValue] as? [String: Any]
        let errorContext = cxRum?[Keys.errorContext.rawValue] as? [String: Any]
        return errorContext?[Keys.isCrash.rawValue] as? Bool ?? false
    }

    private func makeHybridRum(beforeSend: @escaping ([[String: Any]]) -> Void) -> CoralogixRum {
        var opts = makeSamplingOptions(sampleRate: 100, exclude: [])
        opts.beforeSendCallBack = beforeSend
        return CoralogixRum(options: opts, sdkFramework: .reactNative(version: "2.0.0"))
    }

    // MARK: - Hybrid beforeSend bypass

    func test_hybridExport_crashEventBypassesBeforeSend_andUploadsDirectly() throws {
        var captured: [[String: Any]] = []
        coralogixRum = makeHybridRum { captured.append(contentsOf: $0) }
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        exporter.spanUploader = uploader

        let result = exporter.export(
            spans: [makeErrorSpan(isCrash: true), makeSamplingSpan(eventType: .networkRequest)],
            explicitTimeout: nil
        )

        XCTAssertEqual(result, .success)
        XCTAssertEqual(uploader.uploadedEvents.count, 1,
                       "the crash event must upload directly, without the JS round trip")
        XCTAssertTrue(isCrashEvent(try XCTUnwrap(uploader.uploadedEvents.first)))
        XCTAssertEqual(captured.count, 1,
                       "the non-crash event must still take the beforeSend path")
        XCTAssertFalse(isCrashEvent(try XCTUnwrap(captured.first)))
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "crash-id"),
                      "a successful direct upload must confirm crash delivery")

        // The correlation id must NOT reach the wire — it's an internal span
        // attribute used only for confirmation, not mapped into cx_rum.
        let uploadedDescription = String(describing: uploader.uploadedEvents)
        XCTAssertFalse(uploadedDescription.contains("crash-id"),
                       "crash_event_id must not appear in the uploaded payload")
        XCTAssertFalse(uploadedDescription.contains(Keys.crashEventId.rawValue),
                       "crash_event_id key must not appear in the uploaded payload")
    }

    func test_hybridExport_nonCrashError_stillTakesBeforeSendPath() throws {
        var captured: [[String: Any]] = []
        coralogixRum = makeHybridRum { captured.append(contentsOf: $0) }
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        exporter.spanUploader = uploader

        let result = exporter.export(spans: [makeErrorSpan(isCrash: false)], explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        XCTAssertTrue(uploader.uploadedEvents.isEmpty,
                      "non-crash errors must not upload before the JS edit")
        XCTAssertEqual(captured.count, 1)
        XCTAssertFalse(exporter.didConfirmCrashUpload(id: "crash-id"))
    }

    func test_hybridExport_failedCrashUpload_isNotConfirmed_andPropagatesFailure() throws {
        coralogixRum = makeHybridRum { _ in }
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        uploader.result = .failure
        exporter.spanUploader = uploader

        let result = exporter.export(spans: [makeErrorSpan(isCrash: true)], explicitTimeout: nil)

        XCTAssertEqual(result, .failure)
        XCTAssertFalse(exporter.didConfirmCrashUpload(id: "crash-id"),
                       "a failed upload must keep the purge gate closed so the pending report is retried")
    }

    func test_secondCrashFailingUpload_isNotConfirmed_afterFirstCrashSucceeded() throws {
        // Regression for the process-wide-flag bug: a crash that uploads OK must not
        // let a *later* crash whose upload fails be treated as delivered.
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        exporter.spanUploader = uploader

        // Crash A uploads successfully.
        uploader.result = .success
        _ = exporter.export(spans: [makeErrorSpan(isCrash: true, crashEventId: "crash-A")], explicitTimeout: nil)
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "crash-A"))

        // Crash B's upload fails.
        uploader.result = .failure
        _ = exporter.export(spans: [makeErrorSpan(isCrash: true, crashEventId: "crash-B")], explicitTimeout: nil)

        XCTAssertFalse(exporter.didConfirmCrashUpload(id: "crash-B"),
                       "B's failed upload must not inherit A's confirmation")
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "crash-A"),
                      "A stays confirmed independently")
    }

    // MARK: - Native path confirmation

    func test_nativeExport_confirmsCrashUpload_onSuccess() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        exporter.spanUploader = uploader

        let result = exporter.export(spans: [makeErrorSpan(isCrash: true)], explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(uploader.uploadedEvents.count, 1)
        XCTAssertTrue(isCrashEvent(try XCTUnwrap(uploader.uploadedEvents.first)))
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "crash-id"))
    }

    // MARK: - flush()

    /// A recovered PLCrashReporter report whose upload succeeds must be confirmed, because
    /// that confirmation is the only thing that purges it from the device. Without it the
    /// report is kept and re-emitted on every launch for the life of the install, while the
    /// backend records the crash every time.
    /// A crash captured in a sampled-out session is recovered on a later, sampled-in launch
    /// still stamped with the crashed session's decision, so the exporter drops it — correctly.
    /// The report must be released all the same: with the handler installed at image load a
    /// sampled-out session now writes a report at all, and an unconfirmed one is re-parsed,
    /// re-emitted and re-dropped on every launch until another crash overwrites it.
    func test_pendingReportFromSampledOutSession_isDroppedButConfirmed_soTheReportIsPurged() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        exporter.spanUploader = uploader

        let result = exporter.export(spans: [makePendingReportSpan(crashEventId: "sampled-out-report",
                                                                   sessionSampledIn: false)],
                                     explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        XCTAssertTrue(uploader.uploadedEvents.isEmpty,
                      "sampling must still drop the span — resolving the report is not delivering it")
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "sampled-out-report"),
                      "a crash the exporter itself declined to send is finished with; the purge gate must open")
    }

    /// The other half of the same rule: when `.errors` is excluded from sampling the recovered
    /// crash is delivered, not dropped, and is confirmed by the upload rather than by policy.
    func test_pendingReportFromSampledOutSession_isDelivered_whenErrorsAreExcludedFromSampling() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: [.errors]))
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        exporter.spanUploader = uploader

        let result = exporter.export(spans: [makePendingReportSpan(crashEventId: "excluded-report",
                                                                   sessionSampledIn: false)],
                                     explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(uploader.uploadedEvents.count, 1)
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "excluded-report"))
    }

    func test_pendingReportUpload_isConfirmed_soTheReportCanBePurged() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        exporter.spanUploader = uploader

        let result = exporter.export(spans: [makePendingReportSpan()], explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        let uploaded = try XCTUnwrap(uploader.uploadedEvents.first)
        XCTAssertTrue(isCrashEvent(uploaded),
                      "a pending report is reported to the backend as a crash")
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "report-id"),
                      "the SDK must recognise the crash it just uploaded — this is what purges the report")
    }

    /// The confirmation must still be per-report: a failed upload cannot be confirmed, or a
    /// report would be purged before it was ever delivered.
    func test_pendingReportUpload_isNotConfirmed_whenTheUploadFails() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        uploader.result = .failure
        exporter.spanUploader = uploader

        _ = exporter.export(spans: [makePendingReportSpan(crashEventId: "failed-report")], explicitTimeout: nil)

        XCTAssertEqual(uploader.uploadedEvents.count, 1,
                       "the upload must have been attempted, or this proves nothing")
        XCTAssertFalse(exporter.didConfirmCrashUpload(id: "failed-report"),
                       "an unconfirmed report must stay on disk for the next launch")
    }

    func test_flush_forceExportsQueuedSpans_withoutWaitingForScheduleDelay() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        exporter.spanUploader = StubUploader()

        var exportedSpanNames: [String] = []
        CoralogixExporter.testExportCallback = { spans in
            exportedSpanNames.append(contentsOf: spans.map { $0.name })
        }
        defer { CoralogixExporter.testExportCallback = nil }

        coralogixRum.log(severity: .info, message: "queued-before-flush", data: nil, labels: nil)
        XCTAssertTrue(exportedSpanNames.isEmpty,
                      "the span must still be sitting in the batch queue before the flush")

        let flushed = expectation(description: "flush completion")
        coralogixRum.flush { flushed.fulfill() }
        wait(for: [flushed], timeout: 10)

        XCTAssertFalse(exportedSpanNames.isEmpty,
                       "flush must drive queued spans into export without waiting for the schedule delay")
    }

    func test_flush_beforeInit_callsCompletionImmediately() {
        // A CoralogixRum that never completed startup (sampled out) must not hang callers.
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 0, exclude: []))
        CoralogixRum.isInitialized = false

        let flushed = expectation(description: "flush completion")
        rum.flush { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
    }

    /// Spins the run loop until `condition` holds or `timeout` elapses.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    // MARK: - Recovery switch

    func test_shouldRecoverCrashes_followsTheErrorsSwitch_notSampling() {
        XCTAssertTrue(CoralogixRum.shouldRecoverCrashes(options: makeSamplingOptions(sampleRate: 0, exclude: [])),
                      "A sampled-out launch must still recover crashes left by earlier launches.")
        XCTAssertFalse(CoralogixRum.shouldRecoverCrashes(options: makeSamplingOptions(sampleRate: 100,
                                                                                      exclude: [],
                                                                                      instrumentations: [.errors: false])),
                       "instrumentations[.errors] = false must still mean no crash reporting at all.")
    }

    // MARK: - Screenshots on the crash path

    /// `isCrash` is a caller-supplied flag on a public entry point, and the documented hybrid
    /// path — an RN or Flutter host reporting a JS or Dart fatal — passes it while the native
    /// process carries on. The frame from the moment of failure is the most useful artifact
    /// there is for those, so a live crash report captures one like any other error.
    func test_reportCrash_live_capturesAScreenshot() {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        coralogixRum.coralogixExporter?.spanUploader = StubUploader()
        let mockSessionReplay = MockSessionReplay()
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)
        defer { SdkManager.shared.register(sessionReplayInterface: nil) }

        coralogixRum.reportError(message: "fatal-js-error",
                                 stackTrace: [],
                                 errorType: "Error",
                                 isCrash: true)

        XCTAssertTrue(waitUntil { mockSessionReplay.captureEventCalledWith != nil },
                      "a live crash report must capture the screen it crashed on")
    }

}
