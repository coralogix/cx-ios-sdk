//
//  SampledOutExportTests.swift
//
//  End-to-end coverage of what a sampled-out session puts on the wire, matching the browser
//  SDK: with `excludeFromSampling` empty it uploads nothing — not its init, not
//  `session_replay_init` — and with any exclusion the excluded categories and the SDK's own
//  `internal` events are uploaded (except `session_replay_init`, since nothing is recorded), under
//  the normal snapshot rules; a session that later rotates sampled in gets its first snapshot.
//  Drives spans through `CoralogixExporter.export()` and asserts on the encoded `text.cx_rum` payloads a capturing
//  uploader receives, so the snapshot marking is checked as well as the filter.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class SampledOutExportTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
    }

    func testSampledOut_nothingExcluded_uploadsNothing() throws {
        let (rum, exporter, uploader) = try makeSampledOutExporter(exclude: [])
        defer { rum.shutdown() }

        _ = exporter.export(spans: [makeSamplingSpan(eventType: .internalKey, sampledIn: false),
                                    makeSessionReplayInitSpan(sampledIn: false),
                                    makeSamplingSpan(eventType: .log, sampledIn: false)],
                            explicitTimeout: nil)
        XCTAssertTrue(uploader.cxRumPayloads().isEmpty,
                      "A sampled-out session with nothing excluded must upload nothing, init and session_replay_init included.")

        // Control through the same exporter and uploader, so the empty capture above is the
        // filter's doing and not a capture path that records nothing.
        _ = exporter.export(spans: [makeSamplingSpan(eventType: .log, sampledIn: true)], explicitTimeout: nil)
        XCTAssertEqual(uploader.cxRumPayloads().compactMap(eventType), [CoralogixEventType.log.rawValue])
    }

    func testSampledOut_withExclusion_uploadsExcludedCategoryAndInternalEvents() throws {
        let (rum, exporter, uploader) = try makeSampledOutExporter(exclude: [.errors])
        defer { rum.shutdown() }

        // Drain the SDK's own init span first: it is the session's first exported event, so it
        // must arrive as the snapshot — and draining it here keeps it from racing the batch below.
        flush()
        let sdkInit = try XCTUnwrap(uploader.cxRumPayloads().first { internalEventName($0) == Keys.initKey.rawValue },
                                    "With an exclusion, the SDK's init event must upload.")
        XCTAssertEqual(sdkInit[Keys.isSnapshotEvent.rawValue] as? Bool, true,
                       "The session's first uploaded event must still be promoted to a snapshot.")

        _ = exporter.export(spans: [makeSessionReplayInitSpan(sampledIn: false),
                                    makeSamplingSpan(eventType: .error, sampledIn: false),
                                    makeSamplingSpan(eventType: .log, sampledIn: false)],
                            explicitTimeout: nil)

        let payloads = uploader.cxRumPayloads()
        let types = payloads.compactMap(eventType)
        XCTAssertTrue(types.contains(CoralogixEventType.error.rawValue), "The excluded category must upload.")
        XCTAssertFalse(types.contains(CoralogixEventType.log.rawValue), "A category not excluded must still drop.")
        XCTAssertFalse(payloads.contains { internalEventName($0) == Keys.sessionReplayInit.rawValue },
                       "Session Replay records nothing in a sampled-out session, so its init must not upload even with an exclusion.")

        // Control: the same span stamped sampled in must upload through this exporter, so the drop
        // above is the filter's doing and not a payload that never encodes the event name.
        _ = exporter.export(spans: [makeSessionReplayInitSpan(sampledIn: true)], explicitTimeout: nil)
        XCTAssertTrue(uploader.cxRumPayloads().contains { internalEventName($0) == Keys.sessionReplayInit.rawValue },
                      "A sampled-in session_replay_init must upload.")
    }

    func testRotationFromSampledOutToSampledIn_firstEventIsSnapshot() throws {
        let (rum, _, uploader) = try makeSampledOutExporter(exclude: [])
        defer { rum.shutdown() }
        let sessionManager = try XCTUnwrap(rum.sessionManager)
        let sampledOutSessionId = sessionManager.sessionMetadata?.sessionId

        rum.log(severity: .info, message: "sampled-out log")
        flush()
        XCTAssertTrue(uploader.cxRumPayloads().isEmpty,
                      "Nothing from the sampled-out session uploads, the SDK's own init included.")

        sessionManager.samplingRoller = { true }
        rum.createNewSession()
        XCTAssertTrue(sessionManager.isSessionSampledIn, "Precondition: the rotation rolled sampled in.")
        let sampledInSessionId = try XCTUnwrap(sessionManager.sessionMetadata?.sessionId)
        XCTAssertNotEqual(sampledInSessionId, sampledOutSessionId, "Precondition: the rotation started a new session.")

        rum.log(severity: .info, message: "sampled-in log")
        flush()

        let payloads = uploader.cxRumPayloads()
        let first = try XCTUnwrap(payloads.first, "The sampled-in session must upload.")
        XCTAssertEqual(sessionId(first), sampledInSessionId)
        XCTAssertEqual(first[Keys.isSnapshotEvent.rawValue] as? Bool, true,
                       "The first event of the session that rotated in must be a snapshot.")
        XCTAssertTrue(payloads.contains { eventType($0) == CoralogixEventType.log.rawValue && sessionId($0) == sampledInSessionId },
                      "The log sent after the rotation must upload under the new session.")
    }

    // MARK: - Helpers

    private func makeSampledOutExporter(exclude: Set<ExcludableInstrumentation>) throws
        -> (CoralogixRum, CoralogixExporter, CapturingSpanUploader) {
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 0, exclude: exclude))
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = CapturingSpanUploader()
        exporter.spanUploader = uploader
        return (rum, exporter, uploader)
    }

    /// Pushes spans still queued in the batch processor through `export()`.
    private func flush() {
        Thread.sleep(forTimeInterval: 0.3)
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func makeSessionReplayInitSpan(sampledIn: Bool) -> SpanData {
        makeSamplingSpan(eventType: .internalKey, sampledIn: sampledIn, extraAttributes: [
            Keys.internalEventType.rawValue: AttributeValue(Keys.sessionReplayInit.rawValue),
            Keys.internalEventData.rawValue: AttributeValue(Helper.convertDictionaryToJsonString(dict: ["maskAllTexts": true]))
        ])
    }

    private func eventType(_ cxRum: [String: Any]) -> String? {
        (cxRum[Keys.eventContext.rawValue] as? [String: Any])?[Keys.type.rawValue] as? String
    }

    private func sessionId(_ cxRum: [String: Any]) -> String? {
        (cxRum[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.sessionId.rawValue] as? String
    }

    private func internalEventName(_ cxRum: [String: Any]) -> String? {
        (cxRum[Keys.internalContext.rawValue] as? [String: Any])?[Keys.event.rawValue] as? String
    }
}
