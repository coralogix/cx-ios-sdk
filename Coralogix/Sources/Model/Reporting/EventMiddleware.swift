//
//  EventMiddleware.swift
//
//
//  Created by Coralogix DEV TEAM on 26/05/2026.
//

import Foundation

/// One stage of an `EventPipeline`. Receives a `TelemetryEvent`, returns the
/// (possibly transformed) event to forward to the next stage, or `nil` to
/// drop it — which short-circuits the rest of the pipeline.
///
/// Implementations must be pure and synchronous. Concurrency belongs to the
/// pipeline's caller; this protocol promises nothing about threading.
protocol EventMiddleware {
    func process(_ event: TelemetryEvent) -> TelemetryEvent?
}
