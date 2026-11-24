//
//  ANRInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 13/02/2026.
//

import Foundation

extension CoralogixRum {
    /// Initializes ANR (Application Not Responding) detection.
    /// ANR events are reported as error events, not mobile vitals, through `SpanEventReporter`.
    /// Each ANR span is matched to its own delivery, so a hang the process then ends during is
    /// not reported a second time by the next launch.
    public func initializeANRInstrumentation() {
        self.metricsManager.eventReporter = SpanEventReporter(
            createErrorSpan: { [weak self] in
                guard let self = self else { return nil }
                let span = self.makeSpan(event: .error, source: .anr, severity: .error)
                if let exporter = self.coralogixExporter {
                    self.fatalHangWatch.awaitDelivery(ofSpan: span.context.spanId.hexString, through: exporter)
                }
                return span
            }
        )
        self.metricsManager.startANRMonitoring(hangObserver: self.fatalHangWatch)
    }
}
