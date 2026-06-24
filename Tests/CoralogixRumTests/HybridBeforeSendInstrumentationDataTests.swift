//
//  HybridBeforeSendInstrumentationDataTests.swift
//
//  Hybrid (`beforeSendCallBack`) path: spans are encoded *before* the JS edit and the
//  edited batch is handed back through `sendBeforeSendData` to upload. An edit to an
//  editable `cx_rum` field must land in BOTH `text.cx_rum` AND
//  `instrumentation_data.otelSpan.attributes` — the same parity the native single-event
//  `beforeSend` path guarantees (see `BeforeSendInstrumentationDataTests`).
//

import XCTest
import CoralogixInternal
import Foundation

@testable import Coralogix

final class HybridBeforeSendInstrumentationDataTests: XCTestCase {

    private var coralogixRum: CoralogixRum!

    override func tearDownWithError() throws {
        coralogixRum?.shutdown()
        coralogixRum = nil
    }

    // MARK: - Fixtures

    /// Test-only `SpanUploading` that records the final payload handed to upload without
    /// network I/O. `sendBeforeSendData` routes through `spanUploader.upload`, so this
    /// captures exactly what the hybrid path would POST.
    private final class CapturingUploader: SpanUploading {
        private(set) var uploaded: [[String: Any]]?
        func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
            uploaded = spans
            return .success
        }
    }

    /// A real `SpanData` (the `export()` path consumes `[SpanData]`) of the given event type,
    /// carrying the session + http attributes the cx_rum.* mirror reads. network-request /
    /// custom-span are the two types that emit `instrumentation_data`.
    private func makeHybridSpan(eventType: CoralogixEventType) -> SpanData {
        let attributes: [String: AttributeValue] = [
            Keys.eventType.rawValue: AttributeValue(eventType.rawValue),
            Keys.severity.rawValue: AttributeValue("3"),
            Keys.source.rawValue: AttributeValue("fetch"),
            Keys.environment.rawValue: AttributeValue("test"),
            Keys.userId.rawValue: AttributeValue("uid"),
            Keys.userName.rawValue: AttributeValue("Test User"),
            Keys.userEmail.rawValue: AttributeValue("test@example.com"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
            SemanticAttributes.httpUrl.rawValue: AttributeValue("https://example.com/orig"),
            SemanticAttributes.httpMethod.rawValue: AttributeValue("GET"),
            SemanticAttributes.httpStatusCode.rawValue: AttributeValue("200")
        ]
        return SpanData(traceId: TraceId.random(),
                        spanId: SpanId.random(),
                        name: "testSpan_\(eventType.rawValue)",
                        kind: .client,
                        startTime: Date(),
                        attributes: attributes,
                        endTime: Date(),
                        hasEnded: true)
    }

    private func makeHybridRum(captureBatchInto sink: @escaping ([[String: Any]]) -> Void) -> CoralogixRum {
        var opts = makeSamplingOptions(sampleRate: 100, exclude: [])
        opts.beforeSendCallBack = { batch in sink(batch) }
        return CoralogixRum(options: opts, sdkFramework: .reactNative(version: "2.0.0"))
    }

    private func otelAttributes(of event: [String: Any]) throws -> [String: Any] {
        let inst = try XCTUnwrap(event[Keys.instrumentationData.rawValue] as? [String: Any])
        let otel = try XCTUnwrap(inst[Keys.otelSpan.rawValue] as? [String: Any])
        return try XCTUnwrap(otel[Keys.attributes.rawValue] as? [String: Any])
    }

    private func textCxRum(of event: [String: Any]) throws -> [String: Any] {
        let text = try XCTUnwrap(event[Keys.text.rawValue] as? [String: Any])
        return try XCTUnwrap(text[Keys.cxRum.rawValue] as? [String: Any])
    }

    /// Applies `transform` to `event.text.cx_rum`, returning the edited event — the shape a
    /// hybrid bridge produces after the JS edit, before calling back into `sendBeforeSendData`.
    private func editingCxRum(_ event: [String: Any],
                              _ transform: ([String: Any]) -> [String: Any]) throws -> [String: Any] {
        var result = event
        var text = try XCTUnwrap(event[Keys.text.rawValue] as? [String: Any])
        let cxRum = try XCTUnwrap(text[Keys.cxRum.rawValue] as? [String: Any])
        text[Keys.cxRum.rawValue] = transform(cxRum)
        result[Keys.text.rawValue] = text
        return result
    }

    // MARK: - Tests

    /// Primary acceptance: an editable field (user_email) and labels edited on the hybrid
    /// batch propagate into BOTH destinations of the uploaded payload.
    func test_hybridPath_beforeSendEdit_rebuildsOtelSpanAttributes() throws {
        var captured: [[String: Any]] = []
        coralogixRum = makeHybridRum { captured = $0 }
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = CapturingUploader()
        exporter.spanUploader = uploader

        // 1) Encode + hand the batch to the hybrid callback.
        _ = exporter.export(spans: [makeHybridSpan(eventType: .networkRequest)], explicitTimeout: nil)
        XCTAssertEqual(captured.count, 1, "hybrid callback must receive the encoded network span")

        // Falsifiability anchor: before the JS edit, otelSpan.attributes still carry the
        // ORIGINAL email — no rebuild ran at encode time (hybrid uses beforeSendCallBack, not
        // beforeSend). Without the fix, this same value would survive into the upload.
        let preEdit = try otelAttributes(of: captured[0])
        XCTAssertEqual(preEdit["cx_rum.session_context.user_email"] as? String, "test@example.com")

        // 2) JS edits text.cx_rum, then the bridge calls back into sendBeforeSendData.
        let edited = try editingCxRum(captured[0]) { cxRum in
            var c = cxRum
            var session = (c[Keys.sessionContext.rawValue] as? [String: Any]) ?? [:]
            session[Keys.userEmail.rawValue] = "redacted@coralogix.com"
            c[Keys.sessionContext.rawValue] = session
            c[Keys.labels.rawValue] = ["tier": "edited"]
            return c
        }
        exporter.sendBeforeSendData(data: [edited])

        // 3) The uploaded payload reflects the edit in BOTH destinations.
        let uploaded = try XCTUnwrap(uploader.uploaded?.first)

        let cxRum = try textCxRum(of: uploaded)
        let textEmail = (cxRum[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.userEmail.rawValue] as? String
        XCTAssertEqual(textEmail, "redacted@coralogix.com", "text.cx_rum must reflect the JS edit")

        let attrs = try otelAttributes(of: uploaded)
        XCTAssertEqual(attrs["cx_rum.session_context.user_email"] as? String, "redacted@coralogix.com",
                       "otelSpan.attributes must be rebuilt from the edited cx_rum on the hybrid path")
        XCTAssertEqual((attrs["cx_rum.labels"] as? [String: Any])?["tier"] as? String, "edited",
                       "labels edit must propagate into otelSpan.attributes on the hybrid path")
    }

    /// The ticket scope is "events that carry instrumentation_data (network-request,
    /// custom-span)" — custom-span must rebuild the same way as network-request.
    func test_hybridPath_customSpan_rebuildsOtelSpanAttributes() throws {
        var captured: [[String: Any]] = []
        coralogixRum = makeHybridRum { captured = $0 }
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = CapturingUploader()
        exporter.spanUploader = uploader

        _ = exporter.export(spans: [makeHybridSpan(eventType: .customSpan)], explicitTimeout: nil)
        XCTAssertEqual(captured.count, 1, "hybrid callback must receive the encoded custom span")

        let edited = try editingCxRum(captured[0]) { cxRum in
            var c = cxRum
            var session = (c[Keys.sessionContext.rawValue] as? [String: Any]) ?? [:]
            session[Keys.userEmail.rawValue] = "redacted@coralogix.com"
            c[Keys.sessionContext.rawValue] = session
            return c
        }
        exporter.sendBeforeSendData(data: [edited])

        let attrs = try otelAttributes(of: try XCTUnwrap(uploader.uploaded?.first))
        XCTAssertEqual(attrs["cx_rum.session_context.user_email"] as? String, "redacted@coralogix.com",
                       "custom-span otelSpan.attributes must be rebuilt from the edited cx_rum")
    }

    /// Events without instrumentation_data (anything but network-request / custom-span) must
    /// pass through sendBeforeSendData unchanged — no otelSpan section to rebuild, and the
    /// edited text must be uploaded verbatim.
    func test_hybridPath_eventWithoutInstrumentationData_passesThroughUnchanged() throws {
        coralogixRum = makeHybridRum { _ in }
        let exporter = try XCTUnwrap(coralogixRum.coralogixExporter)
        let uploader = CapturingUploader()
        exporter.spanUploader = uploader

        let logEvent: [String: Any] = [
            Keys.text.rawValue: [
                Keys.cxRum.rawValue: [
                    Keys.eventContext.rawValue: [Keys.type.rawValue: CoralogixEventType.log.rawValue],
                    Keys.sessionContext.rawValue: [Keys.userEmail.rawValue: "redacted@coralogix.com"]
                ]
            ]
        ]
        exporter.sendBeforeSendData(data: [logEvent])

        let uploaded = try XCTUnwrap(uploader.uploaded?.first)
        XCTAssertNil(uploaded[Keys.instrumentationData.rawValue],
                     "events without instrumentation_data must not gain an otelSpan section")
        let cxRum = try textCxRum(of: uploaded)
        let email = (cxRum[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.userEmail.rawValue] as? String
        XCTAssertEqual(email, "redacted@coralogix.com", "the edited text must be uploaded verbatim")
    }
}
