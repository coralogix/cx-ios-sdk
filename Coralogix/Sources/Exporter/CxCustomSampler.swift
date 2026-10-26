//
//  CxCustomSampler.swift
//
//  Created by Coralogix DEV TEAM on 26/10/2025.
//

import Foundation
import CoralogixInternal

/// Decides the `traceparent` sampled flag for outgoing requests.
///
/// The flag has to say whether the network RUM event will actually be exported, so the backend knows
/// whether to keep its side of the trace:
///
///     exportsNetworkEvent = sampledIn OR excludes(network)
///     flagsByte           = exportsNetworkEvent ? "01" : "00"
///
/// A not-sampled decision clears the flag on the span context, which is what `W3CTraceContextPropagator`
/// writes as `00`, and keeps the span out of the exporter. The request still carries a `traceparent`:
/// propagation and reporting are separate concerns, and a sampled-out session still has to let the
/// backend stitch the trace together. Mirrors the browser SDK's sampler of the same name.
///
/// **This sampler decides network spans only.** Every other span is always sampled and
/// `CoralogixExporter.passesSessionSampling` keeps deciding whether it is exported. That is not a
/// simplification — a crash recovered on relaunch is built through `makeSpan` and only then re-stamped
/// with the crashed session's decision (`SessionManager.lastLaunchSessionSpanAttributes`). A sampler
/// reading the relaunch's own roll would drop that span before the stamp was applied, and the recovery
/// path would then treat the crash as delivered and purge it — losing it for good.
internal final class CxCustomSampler: Sampler {
    /// Read at decision time rather than captured, so a re-initialized SDK is reflected.
    private let excludeFromSampling: () -> Set<ExcludableInstrumentation>

    internal init(excludeFromSampling: @escaping () -> Set<ExcludableInstrumentation>) {
        self.excludeFromSampling = excludeFromSampling
    }

    internal func shouldSample(parentContext: SpanContext?,
                               traceId: TraceId,
                               name: String,
                               kind: SpanKind,
                               attributes: [String: AttributeValue],
                               parentLinks: [SpanData.Link]) -> Decision {
        // Both reads come from the builder attributes `NetworkInstrumentation.spanCustomizationStatic`
        // set before `startSpan`, never from the live SessionManager. One read means the flag on the
        // wire and the stamp on the exported span always describe the same session, even if the
        // session rotates between the request starting and the span ending.
        guard Self.string(attributes[Keys.eventType.rawValue]) == CoralogixEventType.networkRequest.rawValue else {
            return CxSamplingDecision.sampled
        }

        // Hybrid network spans (`reportHybrid…`) receive their attributes after the span has started,
        // so they do not match above and stay sampled — their traceparent is injected by JS or Dart,
        // not here, and their behaviour is unchanged.
        let sampledIn = Self.string(attributes[Keys.spanSessionSampledIn.rawValue])
            .map { $0 == String(true) } ?? true
        let exportsEvent = sampledIn || self.excludeFromSampling().contains(.network)
        return exportsEvent ? CxSamplingDecision.sampled : CxSamplingDecision.notSampled
    }

    internal var description: String { "CxCustomSampler" }

    private static func string(_ value: AttributeValue?) -> String? {
        guard case let .string(string) = value else { return nil }
        return string
    }
}

/// Sampling decision without attributes. The SDK's own, because the fork's equivalent is private to
/// `Samplers.swift`.
private struct CxSamplingDecision: Decision {
    static let sampled = CxSamplingDecision(isSampled: true)
    static let notSampled = CxSamplingDecision(isSampled: false)

    let isSampled: Bool

    var attributes: [String: AttributeValue] { [:] }
}
