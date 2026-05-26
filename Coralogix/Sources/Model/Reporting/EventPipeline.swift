//
//  EventPipeline.swift
//
//
//  Created by Coralogix DEV TEAM on 26/05/2026.
//

import Foundation

/// Ordered chain of `EventMiddleware` instances. Each middleware sees the
/// output of the previous one; the first `nil` short-circuits and `process`
/// returns `nil`.
///
/// Pure and synchronous — no internal locking. Callers that invoke
/// `add(_:)` or `process(_:)` from multiple threads must provide their own
/// synchronization.
final class EventPipeline {
    private var middlewares: [EventMiddleware] = []

    func add(_ middleware: EventMiddleware) {
        middlewares.append(middleware)
    }

    func process(_ event: TelemetryEvent) -> TelemetryEvent? {
        var current: TelemetryEvent = event
        for middleware in middlewares {
            guard let next = middleware.process(current) else { return nil }
            current = next
        }
        return current
    }
}
