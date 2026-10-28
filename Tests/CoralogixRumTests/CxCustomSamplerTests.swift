//
//  CxCustomSamplerTests.swift
//
//  Unit cover for `CxCustomSampler`, the decision behind the `traceparent` flags byte. Each case calls
//  `shouldSample` directly with the builder attributes `NetworkInstrumentation.spanCustomizationStatic`
//  sets before `startSpan`, so every rule is pinned on its own.
//
//  `NetworkPropagationSamplingTests` covers the same decision end to end, through a real request and
//  the header it puts on the wire.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class CxCustomSamplerTests: XCTestCase {

    // MARK: - Network spans: sampledIn OR excludes(network)

    func testNetworkSpan_sampledIn_isSampled() {
        let sampler = CxCustomSampler(excludeFromSampling: [])

        XCTAssertTrue(isSampled(sampler, attributes: attributes(eventType: .networkRequest, sampledIn: true)))
    }

    func testNetworkSpan_sampledOut_nothingExcluded_isNotSampled() {
        let sampler = CxCustomSampler(excludeFromSampling: [])

        XCTAssertFalse(isSampled(sampler, attributes: attributes(eventType: .networkRequest, sampledIn: false)))
    }

    func testNetworkSpan_sampledOut_networkExcluded_isSampled() {
        let sampler = CxCustomSampler(excludeFromSampling: [.network])

        XCTAssertTrue(isSampled(sampler, attributes: attributes(eventType: .networkRequest, sampledIn: false)))
    }

    /// The rule is `excludes(network)`, not "anything excluded": a sampled-out session that excludes
    /// errors still drops its network events, so the flag must still say `00`.
    func testNetworkSpan_sampledOut_onlyOtherInstrumentationsExcluded_isNotSampled() {
        let others = Set(ExcludableInstrumentation.allCases).subtracting([.network])
        let sampler = CxCustomSampler(excludeFromSampling: others)

        XCTAssertFalse(isSampled(sampler, attributes: attributes(eventType: .networkRequest, sampledIn: false)),
                       "Excluding \(others) must not set the flag on a network span.")
    }

    // MARK: - No session stamp: kept, as the export filter keeps it

    /// `spanCustomizationStatic` writes no stamp when there is no live instance or session yet, and
    /// `passesSessionSampling` exports such a span as sampled in. The sampler has to agree, or the
    /// request goes out with `00` while its span is exported — the one-sided trace the flag prevents.
    func testNetworkSpan_withoutSessionStamp_isSampled_likeTheExportFilter() {
        let unstamped = attributes(eventType: .networkRequest, sampledIn: nil)
        let sampler = CxCustomSampler(excludeFromSampling: [])

        XCTAssertTrue(isSampled(sampler, attributes: unstamped))
        XCTAssertTrue(makeExporter().passesSessionSampling(MockSpanData(attributes: unstamped)),
                      "Sanity: the export filter must keep the same unstamped span, or the two do not match.")
    }

    // MARK: - Non-network spans: always sampled, the export filter decides

    /// A recovered crash is re-stamped with the crashed session's decision only after `startSpan`,
    /// so a sampler that dropped non-network spans on the stamp it sees here would lose it for good.
    func testNonNetworkSpan_sampledOut_nothingExcluded_isSampled() {
        let sampler = CxCustomSampler(excludeFromSampling: [])
        let nonNetwork: [CoralogixEventType] = [.error, .log, .userInteraction, .navigation,
                                                .mobileVitals, .lifeCycle, .customSpan, .internalKey]

        for eventType in nonNetwork {
            XCTAssertTrue(isSampled(sampler, attributes: attributes(eventType: eventType, sampledIn: false)),
                          "\(eventType.rawValue) must stay sampled; only the export filter may drop it.")
        }
    }

    // MARK: - Helpers

    private func isSampled(_ sampler: CxCustomSampler, attributes: [String: AttributeValue]) -> Bool {
        sampler.shouldSample(parentContext: nil,
                             traceId: TraceId.random(),
                             name: Keys.iosSdk.rawValue,
                             kind: .client,
                             attributes: attributes,
                             parentLinks: []).isSampled
    }

    /// Mirrors what `spanCustomizationStatic` puts on the builder: the stamp is a string, as
    /// `SessionManager.sessionSpanAttributes` writes it. `sampledIn: nil` leaves it out.
    private func attributes(eventType: CoralogixEventType, sampledIn: Bool?) -> [String: AttributeValue] {
        var attributes = [Keys.eventType.rawValue: AttributeValue.string(eventType.rawValue)]
        if let sampledIn {
            attributes[Keys.spanSessionSampledIn.rawValue] = .string(String(sampledIn))
        }
        return attributes
    }

    private func makeExporter() -> CoralogixExporter {
        CoralogixExporter(options: makeSamplingOptions(sampleRate: 0, exclude: []),
                          sessionManager: SessionManager(),
                          networkManager: MockNetworkManager(),
                          viewManager: ViewManager(keyChain: nil),
                          metricsManager: MetricsManager())
    }
}
