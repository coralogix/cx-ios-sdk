//
//  EventReporter.swift
//
//
//  Created by Coralogix DEV TEAM on 20/05/2026.
//

import Foundation

/// Receives a typed telemetry event (see `TelemetryEvent`) and turns it into
/// whatever the production SDK does today — a span, a log, or both.
///
/// Replaces the ad-hoc `(String, String) -> Void` / `([String: Any]) -> Void`
/// closures on `MetricsManager`. Concrete implementations decide their own
/// threading; this protocol promises nothing about which queue `report` runs on.
protocol EventReporter {
    func report(_ event: TelemetryEvent)
}
