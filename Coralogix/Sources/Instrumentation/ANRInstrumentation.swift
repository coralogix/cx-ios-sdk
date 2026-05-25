//
//  ANRInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 13/02/2026.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    /// Initializes ANR (Application Not Responding) detection.
    /// ANR events are reported as error events, not mobile vitals.
    ///
    /// CX-40573: ANR events flow through the typed EventReporter
    /// protocol — the orchestrator wires SpanEventReporter here and the
    /// underlying span-building logic lives in that struct. The
    /// `anrErrorClosure` fallback path was removed in CX-43341.
    public func initializeANRInstrumentation() {
        self.metricsManager.eventReporter = SpanEventReporter(
            createErrorSpan: { [weak self] in
                self?.makeSpan(event: .error, source: .code, severity: .error)
            },
            recordScreenshot: { [weak self] span in
                self?.recordScreenshotForSpan(to: &span)
            }
        )
        self.metricsManager.startANRMonitoring()
    }
}
