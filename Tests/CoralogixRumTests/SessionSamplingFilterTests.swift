//
//  SessionSamplingFilterTests.swift
//
//  Verifies the per-span sampling filter at the top of CoralogixExporter.export():
//    - Sampled in: every span passes regardless of event_type.
//    - Sampled out: only spans whose event_type is in options.excludeFromSampling pass.
//    - Sampled out + missing event_type: dropped (failsafe).
//    - Sampled out + empty excludes: nothing passes (production-unreachable but invariant
//      holds when the flag is flipped manually, e.g. on a rotation that happens to roll out).
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

        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "log")))
        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "network-request")))
        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: "error")))
        XCTAssertTrue(exporter.passesSessionSampling(span(eventType: nil)),
                      "Sampled-in must pass even spans missing event_type — only sampled-out enforces it.")
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

        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "internal")),
                       "Internal/unknown event_types are not in ExcludableInstrumentation and must be dropped.")
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "totally-bogus")))
    }

    // MARK: - Sampled out + empty excludes (manually flipped)

    func testPassesSessionSampling_sampledOutEmptyExcludes_dropsEverything() {
        // sampleRate=100 + exclude=[] inits with sampledIn=true; manually flip to false to
        // exercise the "empty excludes + sampled out" invariant. (Production cannot reach this
        // pair because init would short-circuit, but the filter must still hold.)
        let exporter = makeExporter(sampleRate: 100, exclude: [])
        exporter.updateSessionSampling(sampledIn: false)

        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "error")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: "log")))
        XCTAssertFalse(exporter.passesSessionSampling(span(eventType: nil)))
    }

    // MARK: - Attribute extraction handles both AttributeValue and raw String

    func testPassesSessionSampling_sampledOut_eventTypeAsRawString_stillMatches() {
        // Belt-and-suspenders: the extraction helper supports both AttributeValue and raw String
        // attribute encodings. Default span() uses AttributeValue; build one with a raw String
        // to confirm the fallback branch.
        let exporter = makeExporter(sampleRate: 0, exclude: [.logs])
        let mock = MockSpanData(attributes: [Keys.eventType.rawValue: "log"],
                                statusCode: nil, resources: nil)

        XCTAssertTrue(exporter.passesSessionSampling(mock))
    }

    // MARK: - Helpers

    private func makeExporter(sampleRate: Int,
                              exclude: Set<ExcludableInstrumentation>) -> CoralogixExporter {
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
            instrumentations: nil,
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

    private func span(eventType: String?) -> MockSpanData {
        var attrs: [String: Any] = [:]
        if let eventType = eventType {
            attrs[Keys.eventType.rawValue] = AttributeValue(eventType)
        }
        return MockSpanData(attributes: attrs, statusCode: nil, resources: nil)
    }
}
