//
//  SpanMetricsCollector.swift
//
//
//  Created by Coralogix DEV TEAM on 20/05/2026.
//

import Foundation
import CoralogixInternal

/// Production `MetricsCollector` impl. Aggregates the incoming
/// `[VitalsMetric]` back into the `[String: Any]` shape the backend reads
/// today and emits it as a single attribute on a `mobile_vitals` span.
///
/// The dict-shape transform happens in `Array<VitalsMetric>.toDictionary()`
/// so the round-trip can be unit-tested without going through a span;
/// `WireFormatTests` pins the byte-equivalence to the legacy closure path.
///
/// `createSpan` is the only injected dependency — it returns a fresh
/// `mobile_vitals` span ready for attributes. Returns `nil` when the
/// orchestrator (`CoralogixRum`) has been torn down; in that case the
/// metrics are dropped (matches the pre-refactor `[weak self]` behaviour).
final class SpanMetricsCollector: MetricsCollector {
    private let createSpan: () -> (any Span)?

    init(createSpan: @escaping () -> (any Span)?) {
        self.createSpan = createSpan
    }

    func collect(_ metrics: [VitalsMetric]) {
        guard !metrics.isEmpty else { return }
        let dict = metrics.toDictionary()
        // Boundary check: VitalsMetric.payload is Any to accept both dict
        // and array shapes the legacy closure path passed. Anything that
        // isn't JSON-serializable would crash inside JSONSerialization
        // below — drop with a log instead.
        guard JSONSerialization.isValidJSONObject(dict) else {
            Log.d("[SpanMetricsCollector] Non-JSON-serializable payload in metrics \(metrics.map(\.name)); dropping batch")
            return
        }
        guard let span = createSpan() else {
            Log.d("[SpanMetricsCollector] orchestrator gone; dropping \(metrics.count) metric(s)")
            return
        }
        span.setAttribute(
            key: Keys.mobileVitalsType.rawValue,
            value: Helper.convertDictionaryToJsonString(dict: dict)
        )
        span.end()
    }
}
