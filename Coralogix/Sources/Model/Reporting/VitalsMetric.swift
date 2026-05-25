//
//  VitalsMetric.swift
//
//
//  Created by Coralogix DEV TEAM on 20/05/2026.
//

import Foundation

/// A single mobile-vitals category emitted by a detector.
///
/// `name` is the wire-format category key (e.g. `Keys.cpu.rawValue`,
/// `Keys.memory.rawValue`, `Keys.fps.rawValue`). `payload` is the same
/// shape `Detector.statsDictionary()` returns — usually a
/// `[String: Any]` dict, but the hybrid-SDK entry points
/// (`reportMobileVitalsMeasurement(type:metrics:)`) wrap an
/// `[[String: Any]]` array. `payload` is intentionally typed `Any` so
/// either shape reaches the collector unchanged (pinned by
/// `WireFormatTests`).
///
/// - Important: `payload` must be JSON-serializable
///   (`JSONSerialization.isValidJSONObject(["x": payload])` must return
///   true). The production sink `SpanMetricsCollector` validates this at
///   the boundary and drops invalid payloads with a `Log.d`, but callers
///   should still hand in dicts / arrays of strings, numbers, and bools —
///   not class instances, `Decimal`, `Date`, etc.
///
/// Named `VitalsMetric` rather than `Metric` to avoid a filename collision
/// with the bundled OTel SDK's own `Metric.swift`.
struct VitalsMetric {
    let name: String
    let payload: Any
}

extension Array where Element == VitalsMetric {
    /// Re-flattens `[VitalsMetric]` back to the `[String: Any]` shape
    /// `SpanMetricsCollector` JSON-encodes onto the `mobile_vitals` span
    /// attribute. `WireFormatTests` pins the round-trip.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        for metric in self {
            dict[metric.name] = metric.payload
        }
        return dict
    }
}
