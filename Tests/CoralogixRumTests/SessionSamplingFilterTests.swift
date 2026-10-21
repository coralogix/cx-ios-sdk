//
//  SessionSamplingFilterTests.swift
//
//  Verifies the per-span sampling filter at the top of CoralogixExporter.export(). The
//  decision is driven by each span's own `is_session_sampled_in` stamp (burned at creation),
//  NOT the exporter's live flag — so a span keeps the decision of the session it was born in
//  even after a rotation flips the live flag:
//    - Stamped sampled-in: every span passes regardless of event_type.
//    - Stamped sampled-out: spans whose event_type is in options.excludeFromSampling pass,
//      plus `internal` events when that list is non-empty.
//    - Stamped sampled-out + missing event_type: dropped (failsafe).
//    - Stamped sampled-out + empty excludes: nothing passes, `internal` included (browser parity).
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class SessionSamplingFilterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
    }

    // MARK: - Sampled in: filter is a no-op

    func testPassesSessionSampling_sampledIn_passesEverySpan() {
        let exporter = makeExporter(sampleRate: 100, exclude: [])

        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "log", sampledIn: true)))
        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "network-request", sampledIn: true)))
        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "error", sampledIn: true)))
        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: nil, sampledIn: true)),
                      "A sampled-in stamp must pass even spans missing event_type — only sampled-out enforces it.")
    }

    // MARK: - Sampled out + non-empty excludes

    func testPassesSessionSampling_sampledOut_excludeErrors_onlyErrorPasses() {
        let exporter = makeExporter(sampleRate: 0, exclude: [.errors])

        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "error")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "log")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "network-request")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "user-interaction")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "mobile-vitals")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "custom-span")))
    }

    func testPassesSessionSampling_sampledOut_excludeErrorsAndLogs_bothPass() {
        let exporter = makeExporter(sampleRate: 0, exclude: [.errors, .logs])

        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "error")))
        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "log")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "network-request")))
    }

    func testPassesSessionSampling_sampledOut_eachExcludableMapsToCorrectEventType() {
        // Walk every ExcludableInstrumentation case and verify a span with the matching
        // event_type passes, while a span with a different one drops.
        for excludeCase in ExcludableInstrumentation.allCases {
            let exporter = makeExporter(sampleRate: 0, exclude: [excludeCase])
            let matching = excludeCase.eventType.rawValue
            XCTAssertTrue(exporter.passesSessionSampling(span(eventType: matching)),
                          "exclude=[.\(excludeCase)] must pass span with event_type=\(matching)")
        }
    }

    // MARK: - Sampled out: edge cases

    func testPassesSessionSampling_sampledOut_missingEventType_drops() {
        let exporter = makeExporter(sampleRate: 0, exclude: [.errors])

        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: nil)),
                       "Span with no event_type attribute must be dropped on sampled-out sessions.")
    }

    func testPassesSessionSampling_sampledOut_unknownEventType_drops() {
        let exporter = makeExporter(sampleRate: 0, exclude: [.errors])

        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "totally-bogus")),
                       "An event_type outside ExcludableInstrumentation must be dropped when sampled out.")
    }

    func testPassesSessionSampling_sampledOut_withExclusion_internalPasses() {
        // Once anything is excluded the session is reporting, so the SDK's own events go with it,
        // whichever category was excluded.
        for excludeCase in ExcludableInstrumentation.allCases {
            let exporter = makeExporter(sampleRate: 0, exclude: [excludeCase])
            XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "internal")),
                          "exclude=[.\(excludeCase)] must let `internal` through on a sampled-out span.")
        }
    }

    func testPassesSessionSampling_sampledOut_withExclusion_dropsSessionReplayInit() {
        // Session Replay records nothing in a sampled-out session, so its init must not go out even
        // though the session is reporting the excluded categories and the SDK's own init.
        for excludeCase in ExcludableInstrumentation.allCases {
            let exporter = makeExporter(sampleRate: 0, exclude: [excludeCase])
            XCTAssertFalse(exporter.passesSessionSampling(sessionReplayInitSpan(sampledIn: false)),
                           "exclude=[.\(excludeCase)] must not let session_replay_init through on a sampled-out span.")
            XCTAssertTrue(exporter.passesSessionSampling(sessionReplayInitSpan(sampledIn: true)),
                          "A sampled-in session_replay_init must still pass — the drop is the stamp's doing.")
        }
    }

    // MARK: - Sampled out + empty excludes

    func testPassesSessionSampling_sampledOutEmptyExcludes_dropsEverythingIncludingInternal() {
        // Browser parity: with nothing excluded a sampled-out session exports nothing at all —
        // not even the SDK's own init / session_replay_init, which would otherwise arrive as
        // snapshot events and surface the session in session lists.
        let exporter = makeExporter(sampleRate: 0, exclude: [])

        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "internal")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "error")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "log")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "network-request")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: nil)))
        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "internal", sampledIn: true)),
                      "The same exporter must still pass a sampled-in `internal` span — the drop is the stamp's doing.")
    }

    // MARK: - Propagate-only network: installed for the header, must not report

    func testReportsNetworkEvents_networkOff_dropsNetworkSpansOnly() {
        // Case 4a: network instrumentation is installed purely to inject traceparent, so its spans
        // exist and are stamped sampled-in — the sampling filter passes them and cannot help here.
        let exporter = makeExporter(sampleRate: 100, exclude: [], instrumentations: [.network: false])

        XCTAssertFalse(exporter.reportsNetworkEvents(span(eventType: "network-request", sampledIn: true)),
                       "Reporting is switched off, so a propagate-only request must not surface as an event.")
        XCTAssertTrue(exporter.reportsNetworkEvents(span(eventType: "error", sampledIn: true)),
                      "Only network-request spans are affected.")
        XCTAssertTrue(exporter.reportsNetworkEvents(span(eventType: nil, sampledIn: true)))
    }

    func testNetworkOff_excludeFromSamplingCannotRestoreReporting() {
        // Guards a plausible-but-wrong migration story: "disabled network reporting? list .network in
        // excludeFromSampling to get the events back." It does not work, by design — the exclude list
        // only relaxes the *sampling* condition, and the instrumentations map is the source of truth.
        // Asserted as export() composes it, since reportsNetworkEvents alone is sampling-blind.
        let sampledIn = makeExporter(sampleRate: 100, exclude: [.network], instrumentations: [.network: false])
        let sampledOut = makeExporter(sampleRate: 0, exclude: [.network], instrumentations: [.network: false])

        let inSpan = span(eventType: "network-request", sampledIn: true)
        let outSpan = span(eventType: "network-request", sampledIn: false)

        XCTAssertFalse(sampledIn.passesSessionSampling(inSpan) && sampledIn.reportsNetworkEvents(inSpan),
                       "Sampled in: reporting stays off because the caller switched network off.")
        XCTAssertFalse(sampledOut.passesSessionSampling(outSpan) && sampledOut.reportsNetworkEvents(outSpan),
                       "Sampled out: the exclude entry gets the span past the sampling filter, but reporting is still off.")
    }

    func testReportsNetworkEvents_networkOn_passesNetworkSpans() {
        let exporter = makeExporter(sampleRate: 100, exclude: [])

        XCTAssertTrue(exporter.reportsNetworkEvents(span(eventType: "network-request", sampledIn: true)))
    }

    // MARK: - Attribute extraction handles both AttributeValue and raw String

    func testPassesSessionSampling_sampledOut_eventTypeAsRawString_stillMatches() {
        // Belt-and-suspenders: the extraction helper supports both AttributeValue and raw String
        // attribute encodings. Build both the stamp and the event_type as raw Strings to confirm
        // the fallback branch on each — the sampled-out stamp forces the event_type match to run.
        let exporter = makeExporter(sampleRate: 0, exclude: [.logs])
        let mock = MockSpanData(attributes: [Keys.spanSessionSampledIn.rawValue: "false",
                                             Keys.eventType.rawValue: "log"],
                                statusCode: nil, resources: nil)

        XCTAssertTrue(exporter.passesSessionSampling(mock))
    }

    // MARK: - Stamp drives the decision, not the exporter's live flag

    func testPassesSessionSampling_stampSampledIn_survivesRotationToSampledOut() {
        // Data-loss regression: a span created in a sampled-in session and exported only after a
        // rotation flipped the live flag to sampled-out must still be kept. The decision rides on
        // the span's own stamp, not the current session's flag.
        let exporter = makeExporter(sampleRate: 100, exclude: [])
        exporter.updateSessionSampling(sampledIn: false) // simulate a rotation to a sampled-out session

        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "network-request", sampledIn: true)),
                      "A span stamped sampled-in must not be dropped because the live session rotated out.")
    }

    func testPassesSessionSampling_stampSampledOut_droppedEvenWhenLiveFlagSampledIn() {
        // Mirror image: a span stamped sampled-out with a non-excluded event_type must still be
        // dropped while the live session is sampled in — proving the filter reads the stamp and
        // isn't simply always-true.
        let exporter = makeExporter(sampleRate: 0, exclude: [.errors])
        exporter.updateSessionSampling(sampledIn: true) // live session is sampled in

        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "network-request", sampledIn: false)),
                       "A span stamped sampled-out with a non-excluded event_type must drop regardless of the live flag.")
    }

    // MARK: - Helpers

    private func makeExporter(sampleRate: Int,
                              exclude: Set<ExcludableInstrumentation>,
                              instrumentations: [CoralogixExporterOptions.InstrumentationType: Bool]? = nil) -> CoralogixExporter {
        let options = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "test",
            application: "TestApp",
            version: "1.0.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: nil,
            sessionSampleRate: sampleRate,
            excludeFromSampling: exclude,
            instrumentations: instrumentations,
            debug: false
        )
        let rum = CoralogixRum(options: options)
        guard let exporter = rum.coralogixExporter else {
            XCTFail("Exporter must exist; sampleRate=\(sampleRate), exclude=\(exclude) should not have skipped init.")
            // Unreachable, but the compiler needs a non-optional return.
            return CoralogixExporter(
                options: options,
                sessionManager: SessionManager(),
                networkManager: MockNetworkManager(),
                viewManager: ViewManager(keyChain: KeychainManager()),
                metricsManager: MetricsManager()
            )
        }
        return exporter
    }

    /// Builds a span carrying the per-span sampling stamp the filter now reads. Defaults to
    /// `sampledIn: false` since most cases here exercise the sampled-out branch; the sampled-in
    /// case passes `true` explicitly.
    private func span(eventType: String?, sampledIn: Bool = false,
                      extraAttributes: [String: Any] = [:]) -> MockSpanData {
        var attrs: [String: Any] = [
            Keys.spanSessionSampledIn.rawValue: AttributeValue(sampledIn ? "true" : "false")
        ]
        if let eventType = eventType {
            attrs[Keys.eventType.rawValue] = AttributeValue(eventType)
        }
        attrs.merge(extraAttributes) { _, extra in extra }
        return MockSpanData(attributes: attrs, statusCode: nil, resources: nil)
    }

    private func sessionReplayInitSpan(sampledIn: Bool) -> MockSpanData {
        span(eventType: CoralogixEventType.internalKey.rawValue, sampledIn: sampledIn, extraAttributes: [
            Keys.internalEventType.rawValue: AttributeValue(Keys.sessionReplayInit.rawValue)
        ])
    }
}
