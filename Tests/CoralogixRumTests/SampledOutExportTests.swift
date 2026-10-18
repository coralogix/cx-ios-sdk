//
//  SampledOutExportTests.swift
//
//  End-to-end coverage of what a sampled-out session puts on the wire, matching the browser
//  SDK: with `excludeFromSampling` empty it uploads nothing — not its init, not
//  `session_replay_init` — and with any exclusion the excluded categories and the SDK's own
//  `internal` events are uploaded, under the normal snapshot rules. Drives spans through
//  `CoralogixExporter.export()` and asserts on the encoded `text.cx_rum` payloads a capturing
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

        _ = exporter.export(spans: [makeSamplingSpan(eventType: .internalKey, sampledIn: false),
                                    makeSessionReplayInitSpan(sampledIn: false),
                                    makeSamplingSpan(eventType: .error, sampledIn: false),
                                    makeSamplingSpan(eventType: .log, sampledIn: false)],
                            explicitTimeout: nil)

        // The SDK's own init span reaches this uploader asynchronously through the batch
        // processor, so assert on membership rather than an exact list.
        let payloads = uploader.cxRumPayloads()
        let types = payloads.compactMap(eventType)
        XCTAssertTrue(types.contains(CoralogixEventType.error.rawValue), "The excluded category must upload.")
        XCTAssertFalse(types.contains(CoralogixEventType.log.rawValue), "A category not excluded must still drop.")

        let internalEvents = Set(payloads.compactMap(internalEventName))
        XCTAssertTrue(internalEvents.isSuperset(of: [Keys.initKey.rawValue, Keys.sessionReplayInit.rawValue]),
                      "With an exclusion, both init and session_replay_init must upload; got \(internalEvents).")
        XCTAssertTrue(payloads.contains { $0[Keys.isSnapshotEvent.rawValue] as? Bool == true },
                      "The session's first uploaded event must still be promoted to a snapshot.")
    }

    func testRotationFromSampledOutToSampledIn_firstEventIsSnapshot() throws {
        let (rum, exporter, uploader) = try makeSampledOutExporter(exclude: [])
        defer { rum.shutdown() }

        _ = exporter.export(spans: [makeSamplingSpan(eventType: .internalKey, sampledIn: false)], explicitTimeout: nil)
        rum.createNewSession()
        _ = exporter.export(spans: [makeSamplingSpan(eventType: .log, sampledIn: true)], explicitTimeout: nil)

        let payloads = uploader.cxRumPayloads()
        XCTAssertEqual(payloads.compactMap(eventType), [CoralogixEventType.log.rawValue],
                       "Only the sampled-in session's event uploads; the sampled-out init stays dropped.")
        XCTAssertEqual(payloads.first?[Keys.isSnapshotEvent.rawValue] as? Bool, true,
                       "The first event of the session that rotated in must be a snapshot.")
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

    private func makeSessionReplayInitSpan(sampledIn: Bool) -> SpanData {
        makeSamplingSpan(eventType: .internalKey, sampledIn: sampledIn, extraAttributes: [
            Keys.internalEventType.rawValue: AttributeValue(Keys.sessionReplayInit.rawValue),
            Keys.internalEventData.rawValue: AttributeValue(Helper.convertDictionaryToJsonString(dict: ["maskAllTexts": true]))
        ])
    }

    private func eventType(_ cxRum: [String: Any]) -> String? {
        (cxRum[Keys.eventContext.rawValue] as? [String: Any])?[Keys.type.rawValue] as? String
    }

    private func internalEventName(_ cxRum: [String: Any]) -> String? {
        (cxRum[Keys.internalContext.rawValue] as? [String: Any])?[Keys.event.rawValue] as? String
    }
}
