//
//  SessionReplayInitLogTests.swift
//
//  End-to-end coverage for the session-replay init log (CX-44984). Drives a span carrying the
//  `internal_event_type` / `internal_event_data` attributes through `CoralogixExporter.export()`
//  and asserts the decoded payload lands on the wire under `text.cx_rum.internal_context` —
//  the exact gap that silently dropped the payload on Android (CX-44992, lesson #1).
//
//  Asserts on the uploaded wire dict (not `beforeSend`, which on Android could not see
//  internal_context — lesson #2), via a capturing `SpanUploading` mock.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class SessionReplayInitLogTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
    }

    func testSessionReplayInit_landsInternalContextOnWire() throws {
        let uploader = CapturingSpanUploader()
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        defer { rum.shutdown() }

        let exporter = try XCTUnwrap(rum.coralogixExporter, "Exporter must exist after init.")
        exporter.spanUploader = uploader

        let snapshot: [String: Any] = [
            Keys.srRecordingType.rawValue: Keys.image.rawValue,
            Keys.srCaptureScale.rawValue: 2.0,
            Keys.srCaptureCompressQuality.rawValue: 0.8,
            Keys.srSessionRecordingSampleRate.rawValue: 100,
            Keys.srAutoStartSessionRecording.rawValue: true,
            Keys.srTextsToMask.rawValue: ["password"],
            Keys.srMaskAllImages.rawValue: true,
            Keys.srMaskOnlyCreditCards.rawValue: false,
            Keys.srMaskFaces.rawValue: false,
            Keys.srCreditCardPredicate.rawValue: [],
            Keys.srHasFlutterViewBitmapProvider.rawValue: false
        ]

        _ = exporter.export(spans: [makeSessionReplayInitSpan(snapshot: snapshot)], explicitTimeout: nil)

        let internalContext = try XCTUnwrap(uploader.firstInternalContext(),
                                            "internal_context must land on the wire for a session_replay_init span.")

        XCTAssertEqual(internalContext[Keys.event.rawValue] as? String, Keys.sessionReplayInit.rawValue,
                       "internal_context.event must carry the session_replay_init discriminator.")

        let data = try XCTUnwrap(internalContext[Keys.data.rawValue] as? [String: Any],
                                 "internal_context.data must carry the snapshot.")
        XCTAssertEqual(data[Keys.srCaptureScale.rawValue] as? Double, 2.0)
        XCTAssertEqual(data[Keys.srCaptureCompressQuality.rawValue] as? Double, 0.8)
        XCTAssertEqual(data[Keys.srSessionRecordingSampleRate.rawValue] as? Int, 100)
        XCTAssertEqual(data[Keys.srAutoStartSessionRecording.rawValue] as? Bool, true)
        XCTAssertEqual(data[Keys.srTextsToMask.rawValue] as? [String], ["password"])
        XCTAssertEqual(data[Keys.srMaskAllImages.rawValue] as? Bool, true)
        XCTAssertEqual(data[Keys.srHasFlutterViewBitmapProvider.rawValue] as? Bool, false)
    }

    func testSdkInit_stillEmitsInitEventName() throws {
        // The shared internal-context branch must not regress the existing SDK-init log: a span
        // with no internal_event_type attribute still resolves to event "init".
        let uploader = CapturingSpanUploader()
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        defer { rum.shutdown() }

        let exporter = try XCTUnwrap(rum.coralogixExporter)
        exporter.spanUploader = uploader

        _ = exporter.export(spans: [makeSamplingSpan(eventType: .internalKey)], explicitTimeout: nil)

        let internalContext = try XCTUnwrap(uploader.firstInternalContext())
        XCTAssertEqual(internalContext[Keys.event.rawValue] as? String, Keys.initKey.rawValue,
                       "SDK-init log must still resolve to the \"init\" event name.")
    }

    // MARK: - Helpers

    private func makeSessionReplayInitSpan(snapshot: [String: Any]) -> SpanData {
        let attributes: [String: AttributeValue] = [
            Keys.eventType.rawValue: AttributeValue(CoralogixEventType.internalKey.rawValue),
            Keys.internalEventType.rawValue: AttributeValue(Keys.sessionReplayInit.rawValue),
            Keys.internalEventData.rawValue: AttributeValue(Helper.convertDictionaryToJsonString(dict: snapshot)),
            Keys.severity.rawValue: AttributeValue("3"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.environment.rawValue: AttributeValue("test"),
            Keys.userId.rawValue: AttributeValue("uid"),
            Keys.userName.rawValue: AttributeValue("Test User"),
            Keys.userEmail.rawValue: AttributeValue("test@example.com"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200")
        ]
        return SpanData(traceId: TraceId.random(),
                        spanId: SpanId.random(),
                        name: "sessionReplayInitSpan",
                        kind: .client,
                        startTime: Date(),
                        attributes: attributes,
                        endTime: Date(),
                        hasEnded: true)
    }
}

/// Test-only `SpanUploading` that captures the encoded wire dicts so tests can assert on the
/// final `text.cx_rum.*` payload (the actual ingest shape), without network I/O.
final class CapturingSpanUploader: SpanUploading {
    private let lock = NSLock()
    private var uploaded: [[String: Any]] = []

    func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
        lock.lock(); defer { lock.unlock() }
        uploaded.append(contentsOf: spans)
        return .success
    }

    func firstInternalContext() -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        for span in uploaded {
            guard let text = span[Keys.text.rawValue] as? [String: Any],
                  let cxRum = text[Keys.cxRum.rawValue] as? [String: Any],
                  let internalContext = cxRum[Keys.internalContext.rawValue] as? [String: Any] else {
                continue
            }
            return internalContext
        }
        return nil
    }
}
