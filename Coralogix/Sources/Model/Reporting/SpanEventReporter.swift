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
/// `ANRErrorEvent` is wired through this path. The switch on
/// `event.type` is exhaustive (no `default:`) so adding a new
/// `CoralogixEventType` case fails to compile here until a contributor
/// explicitly handles it — either with a new `case` or by adding it to
/// the drop list. Prevents silent mis-routing as the event taxonomy
/// grows.
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
        switch event.type {
        case .error:
            guard let anr = event as? ANRErrorEvent else {
                Log.d("[SpanEventReporter] event.type=.error but concrete type is not ANRErrorEvent; dropping")
                return
            }
            guard var span = createErrorSpan() else { return }
            span.setAttribute(key: Keys.errorMessage.rawValue, value: anr.errorMessage)
            span.setAttribute(key: Keys.errorType.rawValue,    value: anr.errorType)
            recordScreenshot(&span)
            span.end()

        // These event types do not flow through the EventReporter
        // protocol path today — they emit spans via other code paths.
        // Enumerated explicitly (rather than caught by `default:`) so
        // adding a new `CoralogixEventType` case forces a compile-time
        // decision here.
        case .networkRequest, .log, .userInteraction, .webVitals, .longtask, .resources,
             .internalKey, .navigation, .mobileVitals, .lifeCycle, .screenshot,
             .customMeasurement, .customSpan, .unknown:
            Log.d("[SpanEventReporter] event.type=\(event.type.rawValue) is not handled by the protocol path; dropping")
        }
    }
}
