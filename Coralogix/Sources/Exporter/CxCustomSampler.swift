//
//  CxCustomSampler.swift
//
//  Created by Coralogix DEV TEAM on 26/10/2025.
//

import Foundation
import CoralogixInternal

/// Decides the `traceparent` sampled flag for outgoing requests.
///
/// The flag carries the session's sampling decision for that request, so the backend can tell a
/// propagate-only request from a reported one:
///
///     reportsNetworkEvent = sampledIn OR excludes(network)
///     flagsByte           = reportsNetworkEvent ? "01" : "00"
///
/// A not-sampled decision clears the flag on the span context, which is what `W3CTraceContextPropagator`
/// writes as `00`, and keeps the span out of the exporter. Mirrors the browser SDK's sampler of the same
/// name.
///
/// Two things this decision does *not* settle:
///
/// - **Whether a `traceparent` is sent at all.** `shouldAddTraceParentStatic` gates propagation per
///   request, separately and later: a Coralogix-domain URL, a URL matched by `ignoreUrls`,
///   `traceParentInHeader` off, or a URL outside `allowedTracingUrls` means no header whatever was
///   decided here. Flutter injects its own header from Dart and an existing one wins, so this decision
///   is discarded there; React Native on iOS does not instrument fetch itself, so it is not.
/// - **Whether the event arrives.** The flag is fixed at span creation, while a `beforeSend` returning
///   nil and an idle session each drop a reported event afterwards. Neither is knowable this early.
///
/// **This sampler decides network spans only.** Every other span is always sampled and
/// `CoralogixExporter.passesSessionSampling` keeps deciding whether it is exported. That is not a
/// simplification — a crash recovered on relaunch is built through `makeSpan` and only then re-stamped
/// with the crashed session's decision (`SessionManager.lastLaunchSessionSpanAttributes`). A sampler
/// reading the relaunch's own roll would drop that span before the stamp was applied, and the recovery
/// path would then treat the crash as delivered and purge it — losing it for good.
internal final class CxCustomSampler: Sampler {
    /// Snapshot rather than a live read: `excludeFromSampling` is assigned in
    /// `CoralogixExporterOptions.init` and never mutated — the only writers touch `userContext`,
    /// `labels`, `application` and `version` — and a re-initialized SDK builds a new provider and a new
    /// sampler anyway, so there is nothing a live read could pick up.
    private let excludeFromSampling: Set<ExcludableInstrumentation>

    internal init(excludeFromSampling: Set<ExcludableInstrumentation>) {
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
        //
        // `description` rather than a `.string` pattern match, so this parses the attribute exactly as
        // `CoralogixExporter.attributeStringValue` does. Two readers of one stamp that disagree on its
        // encoding would put a flag on the wire that the export decision contradicts.
        guard attributes[Keys.eventType.rawValue]?.description == CoralogixEventType.networkRequest.rawValue else {
            return Samplers.alwaysOnDecision
        }

        // Hybrid network spans (`reportHybrid…`) receive their attributes after the span has started,
        // so they do not match above and stay sampled.
        let stamp = attributes[Keys.spanSessionSampledIn.rawValue]?.description
        let sampledIn = stamp.map { $0 == String(true) } ?? true
        // Keyed on the event type, exactly as `passesSessionSampling` resolves it, so a future case that
        // also maps to `network-request` cannot make the flag and the export decision disagree.
        let exportsEvent = sampledIn || self.excludeFromSampling.contains { $0.eventType == .networkRequest }
        return exportsEvent ? Samplers.alwaysOnDecision : Samplers.alwaysOffDecision
    }

    internal var description: String { "CxCustomSampler" }
}
