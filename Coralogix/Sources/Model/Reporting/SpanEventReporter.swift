//
//  SpanEventReporter.swift
//
//
//  Created by Coralogix DEV TEAM on 20/05/2026.
//

import Foundation
import CoralogixInternal

/// Production `EventReporter` impl. Turns a `TelemetryEvent` into an
/// error span via the orchestrator's `makeSpan`. Today only
/// `ANRErrorEvent` is wired through this path; the switch is deliberately
/// conservative so any new event type is logged and dropped rather than
/// silently mis-routed. Add new event handlers as their producers come
/// online.
///
/// `createSpan` and `recordScreenshot` are injected closures — they let
/// this struct stay decoupled from `CoralogixRum`'s API surface while
/// using its internal `makeSpan` / `recordScreenshotForSpan` methods.
final class SpanEventReporter: EventReporter {
    private let createErrorSpan: () -> (any Span)?
    private let recordScreenshot: (inout any Span) -> Void

    init(createErrorSpan: @escaping () -> (any Span)?,
         recordScreenshot: @escaping (inout any Span) -> Void) {
        self.createErrorSpan = createErrorSpan
        self.recordScreenshot = recordScreenshot
    }

    func report(_ event: TelemetryEvent) {
        if let anr = event as? ANRErrorEvent {
            guard var span = createErrorSpan() else { return }
            span.setAttribute(key: Keys.errorMessage.rawValue, value: anr.errorMessage)
            span.setAttribute(key: Keys.errorType.rawValue,    value: anr.errorType)
            recordScreenshot(&span)
            span.end()
            return
        }
        Log.d("[SpanEventReporter] Unhandled event type \(event.type.rawValue); dropping")
    }
}
