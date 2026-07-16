//
//  CrashDeliveryTests.swift
//
//  Crash events (`error_context.is_crash`) must survive process death:
//  - hybrid path: they bypass the beforeSend JS round trip and upload directly,
//    since the process is usually dying when a crash is exported
//  - the exporter confirms a successful crash upload (`didUploadCrashEvents`),
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
        func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
            uploadedBatches.append(spans)
            return result
        }
        var uploadedEvents: [[String: Any]] { uploadedBatches.flatMap { $0 } }
    }

    /// An error-event `SpanData` that survives the encoding pipeline
    /// (`CxRumBuilder.build()` requires session attributes) and carries the
    /// `is_crash` flag under test.
    private func makeErrorSpan(isCrash: Bool) -> SpanData {
        let attributes: [String: AttributeValue] = [
            Keys.eventType.rawValue: AttributeValue(CoralogixEventType.error.rawValue),
            Keys.severity.rawValue: AttributeValue("5"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.environment.rawValue: AttributeValue("test"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
            Keys.errorMessage.rawValue: AttributeValue("crash-delivery-test"),
            Keys.isCrash.rawValue: AttributeValue.bool(isCrash)
        ]
        return SpanData(traceId: TraceId.random(),
                        spanId: SpanId.random(),
                        name: "errorSpan_isCrash_\(isCrash)",
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
        XCTAssertTrue(exporter.didUploadCrashEvents,
                      "a successful direct upload must confirm crash delivery")
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
        XCTAssertFalse(exporter.didUploadCrashEvents)
    }

    func test_hybridExport_failedCrashUpload_isNotConfirmed_andPropagatesFailure() throws {
        coralogixRum = makeHybridRum { _ in }
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = StubUploader()
        uploader.result = .failure
        exporter.spanUploader = uploader

        let result = exporter.export(spans: [makeErrorSpan(isCrash: true)], explicitTimeout: nil)

        XCTAssertEqual(result, .failure)
        XCTAssertFalse(exporter.didUploadCrashEvents,
                       "a failed upload must keep the purge gate closed so the pending report is retried")
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
        XCTAssertTrue(exporter.didUploadCrashEvents)
    }

    // MARK: - flush()

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

    // MARK: - Crash-event persistence (CrashEventStore)

    private func makeTempStore() -> CrashEventStore {
        return CrashEventStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
    }

    /// Spins the run loop until `condition` holds or `timeout` elapses.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    func test_crashEventStore_roundtripAndClear() {
        let store = makeTempStore()
        XCTAssertTrue(store.loadAll().isEmpty)

        store.append(["error_message": "boom", "crash_timestamp": "123"])
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?["error_message"] as? String, "boom")

        store.clear()
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_crashEventStore_discardsCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CrashEventStore(directory: dir)
        let file = dir.appendingPathComponent("CoralogixRum/pending_crash_events.json")
        try XCTUnwrap("not-json".data(using: .utf8)).write(to: file)

        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "a corrupt store must be discarded so it isn't rescanned every launch")
    }

    func test_reportCrash_persistsEvenWithNonJsonSafeCustomAttributes() {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let uploader = StubUploader()
        uploader.result = .failure
        coralogixRum.coralogixExporter?.spanUploader = uploader
        let store = makeTempStore()
        coralogixRum.crashEventStore = store

        coralogixRum.reportError(message: "fatal-with-date-attr",
                                 stackTrace: [],
                                 errorType: "Error",
                                 isCrash: true,
                                 customAttributes: ["when": Date(), "tag": "x"])

        let persisted = store.loadAll()
        XCTAssertEqual(persisted.count, 1,
                       "attributes JSONSerialization rejects must not abort the crash persist")
        XCTAssertEqual(persisted.first?[Keys.errorMessage.rawValue] as? String, "fatal-with-date-attr")
    }

    func test_reportCrash_persistsToDisk_evenWhenUploadFails() {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let uploader = StubUploader()
        uploader.result = .failure
        coralogixRum.coralogixExporter?.spanUploader = uploader
        let store = makeTempStore()
        coralogixRum.crashEventStore = store

        coralogixRum.reportError(message: "fatal-js-error",
                                 stackTrace: [],
                                 errorType: "Error",
                                 isCrash: true)

        // Persisting happens synchronously inside reportError, before any upload
        // attempt — this is the delivery guarantee for a dying process.
        let persisted = store.loadAll()
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?[Keys.errorMessage.rawValue] as? String, "fatal-js-error")
        XCTAssertNotNil(persisted.first?[Keys.crashTimestamp.rawValue])

        // The upload failed, so the stored copy must survive for the next launch.
        _ = waitUntil(timeout: 2) { !uploader.uploadedBatches.isEmpty }
        XCTAssertEqual(store.loadAll().count, 1)
    }

    func test_reportCrash_clearsStore_onceUploadIsConfirmed() {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let uploader = StubUploader()
        coralogixRum.coralogixExporter?.spanUploader = uploader
        let store = makeTempStore()
        coralogixRum.crashEventStore = store

        coralogixRum.reportError(message: "fatal-js-error",
                                 stackTrace: [],
                                 errorType: "Error",
                                 isCrash: true)

        XCTAssertTrue(waitUntil { store.loadAll().isEmpty },
                      "the stored copy must be cleared after the upload is confirmed")
        XCTAssertTrue(coralogixRum.coralogixExporter?.didUploadCrashEvents == true)
    }

    func test_resendStoredCrashEvents_uploadsWithOriginalTimestamp_andClearsOnConfirm() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let uploader = StubUploader()
        coralogixRum.coralogixExporter?.spanUploader = uploader
        let store = makeTempStore()
        coralogixRum.crashEventStore = store
        store.append([
            Keys.errorMessage.rawValue: "crash-from-previous-launch",
            Keys.errorType.rawValue: "Error",
            Keys.crashTimestamp.rawValue: "1700000000000"
        ])

        var recoveredSpanStart: Date?
        CoralogixExporter.testExportCallback = { spans in
            if let crashSpan = spans.first(where: { $0.attributes[Keys.isCrash.rawValue]?.description == "true" }) {
                recoveredSpanStart = crashSpan.startTime
            }
        }
        defer { CoralogixExporter.testExportCallback = nil }

        coralogixRum.resendPendingStoredCrashEvents()
        coralogixRum.completeCrashRecovery()

        XCTAssertTrue(waitUntil { store.loadAll().isEmpty },
                      "confirmed recovery upload must clear the store")
        // The recovery flush also drains other queued spans (e.g. the init span) —
        // locate the crash event rather than assuming batch order.
        let uploaded = try XCTUnwrap(uploader.uploadedEvents.first(where: { isCrashEvent($0) }))
        let text = uploaded[Keys.text.rawValue] as? [String: Any]
        let cxRum = text?[Keys.cxRum.rawValue] as? [String: Any]
        let errorContext = cxRum?[Keys.errorContext.rawValue] as? [String: Any]
        XCTAssertEqual(errorContext?[Keys.errorMessage.rawValue] as? String, "crash-from-previous-launch")
        XCTAssertEqual(errorContext?[Keys.crashTimestamp.rawValue] as? String, "1700000000000",
                       "re-sent events must keep the original crash time")
        // The recovered span itself is anchored to the crash time (not resend time),
        // mirroring the PLCrashReporter treatment — this is what puts the event
        // under the crash's own timestamp in the platform.
        let spanStart = try XCTUnwrap(recoveredSpanStart)
        XCTAssertEqual(spanStart.timeIntervalSince1970, 1_700_000_000.0, accuracy: 0.001,
                       "re-sent crash span must start at the original crash time")
    }

    func test_resendStoredCrashEvents_keepsStore_whenUploadFails() {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let uploader = StubUploader()
        uploader.result = .failure
        coralogixRum.coralogixExporter?.spanUploader = uploader
        let store = makeTempStore()
        coralogixRum.crashEventStore = store
        store.append([Keys.errorMessage.rawValue: "crash-from-previous-launch"])

        coralogixRum.resendPendingStoredCrashEvents()
        coralogixRum.completeCrashRecovery()

        _ = waitUntil(timeout: 2) { !uploader.uploadedBatches.isEmpty }
        XCTAssertEqual(store.loadAll().count, 1,
                       "unconfirmed recovery must keep the stored copy for the next launch")
    }
}
