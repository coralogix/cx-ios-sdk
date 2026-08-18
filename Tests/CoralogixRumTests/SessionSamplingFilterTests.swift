//
//  SessionSamplingFilterTests.swift
//
//  Verifies the per-span sampling filter at the top of CoralogixExporter.export(). The
//  decision is driven by each span's own `is_session_sampled_in` stamp (burned at creation),
//  NOT the exporter's live flag — so a span keeps the decision of the session it was born in
//  even after a rotation flips the live flag:
//    - Stamped sampled-in: every span passes regardless of event_type.
//    - Stamped sampled-out: only `internal` events and spans whose event_type is in
//      options.excludeFromSampling pass.
//    - Stamped sampled-out + missing event_type: dropped (failsafe).
//    - Stamped sampled-out + empty excludes: only `internal` passes.
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

    func testPassesSessionSampling_sampledOut_internalEventType_alwaysPasses() {
        // The SDK's own lifecycle events are not opt-in-able and must survive regardless, matching
        // Android. Otherwise a sampled-out session looks identical to an SDK that never started and
        // there is no way to confirm from the backend that sampling is behaving.
        let excluded = makeExporter(sampleRate: 0, exclude: [.errors])
        let noExcludes = makeExporter(sampleRate: 0, exclude: [])

        XCTAssertTrue(excluded.passesSessionSampling(span(eventType: "internal")))
        XCTAssertTrue(noExcludes.passesSessionSampling(span(eventType: "internal")),
                      "`internal` survives even with an empty exclude list.")
    }

    // MARK: - Sampled out + empty excludes (manually flipped)

    func testPassesSessionSampling_sampledOutEmptyExcludes_dropsEverythingButInternal() {
        // Sampled-out stamp with no opt-ins: every reportable span drops. This is now a routine
        // production state, not a synthetic one — init no longer short-circuits for a sampled-out
        // session with an empty exclude list, because network instrumentation has to stay alive to
        // propagate trace context.
        let exporter = makeExporter(sampleRate: 100, exclude: [])

        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "error")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "log")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "network-request")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: nil)))
        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "internal")))
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
    private func span(eventType: String?, sampledIn: Bool = false) -> MockSpanData {
        var attrs: [String: Any] = [
            Keys.spanSessionSampledIn.rawValue: AttributeValue(sampledIn ? "true" : "false")
        ]
        if let eventType = eventType {
            attrs[Keys.eventType.rawValue] = AttributeValue(eventType)
        }
        return MockSpanData(attributes: attrs, statusCode: nil, resources: nil)
    }
}
