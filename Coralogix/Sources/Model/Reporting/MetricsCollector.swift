//
//  MetricsCollector.swift
//
//
//  Created by Coralogix DEV TEAM on 20/05/2026.
//

import Foundation

/// Receives a batch of mobile-vitals metrics (one `VitalsMetric` per
/// category). The wire format is pinned by `WireFormatTests`.
/// Concrete implementations decide their own threading.
protocol MetricsCollector {
    func collect(_ metrics: [VitalsMetric])
}
