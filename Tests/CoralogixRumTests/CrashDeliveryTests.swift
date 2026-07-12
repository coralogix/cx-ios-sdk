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
}
