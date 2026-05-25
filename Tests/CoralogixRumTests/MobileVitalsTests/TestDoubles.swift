//
//  TestDoubles.swift
//
//
//  Created by Coralogix DEV TEAM on 25/05/2026.
//
//  Shared `MetricsCollector` / `EventReporter` test doubles. Used by
//  `WireFormatTests` and `MetricsManagerTests` to inspect what the
//  production code emits through the protocol-typed sinks. Promoted
//  from file-private in CX-43341 once a second caller appeared.

import Foundation
@testable import Coralogix

/// Records each `collect(_:)` call as a separate batch so tests can
/// assert both *what* was emitted and *how many times*. Production uses
/// `SpanMetricsCollector`.
///
/// A class (not struct) so callers hold a single reference and observe
/// mutations from background-thread emissions.
final class BatchRecordingCollector: MetricsCollector {
    var batches: [[VitalsMetric]] = []
    func collect(_ metrics: [VitalsMetric]) {
        batches.append(metrics)
    }
}

/// Records a `TelemetryEvent` for assertions. Test-target only.
struct RecordingEventReporter: EventReporter {
    let onEvent: (TelemetryEvent) -> Void
    func report(_ event: TelemetryEvent) {
        onEvent(event)
    }
}
