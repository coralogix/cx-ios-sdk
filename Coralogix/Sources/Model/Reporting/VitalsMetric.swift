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
/// shape `Detector.statsDictionary()` returns today — usually a
/// `[String: Any]` dict, but the hybrid-SDK entry points
/// (`reportMobileVitalsMeasurement(type:metrics:)`) wrap an
/// `[[String: Any]]` array. `payload` is therefore typed `Any` to match
/// every shape the legacy `metricsManagerClosure` accepted; the type is
/// intentionally untyped at this phase so wire compatibility with the
/// pre-refactor path is byte-identical (pinned by `WireFormatTests`).
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
    /// Re-flattens `[VitalsMetric]` back to the `[String: Any]` shape the
    /// legacy `metricsManagerClosure` path emitted. `SpanMetricsCollector`
    /// uses this transform on the wire; `WireFormatTests` pins it to be
    /// byte-identical to the pre-refactor payload.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        for metric in self {
            dict[metric.name] = metric.payload
        }
        return dict
    }
}
