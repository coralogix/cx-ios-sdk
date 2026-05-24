//
//  MetricsCollector.swift
//
//
//  Created by Coralogix DEV TEAM on 20/05/2026.
//

import Foundation

/// Receives a batch of mobile-vitals metrics (one `VitalsMetric` per
/// category). Replaces `MetricsManager.metricsManagerClosure` with a
/// protocol-typed dependency.
///
/// `collect` must produce a payload byte-identical to what the legacy
/// closure path emits today — the wire format is pinned by
/// `WireFormatTests`. Concrete implementations decide their own threading.
protocol MetricsCollector {
    func collect(_ metrics: [VitalsMetric])
}
