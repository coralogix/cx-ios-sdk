//
//  MobileVitalsInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 10/09/2024.
//

import Foundation

extension CoralogixRum {
    public func initializeMobileVitalsInstrumentation() {
        if self.options.shouldInitInstumentation(instumentation: .mobileVitals) {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleMobileVitalsNotification(notification:)),
                                                   name: .cxRumNotificationMetrics, object: nil)
        }
    }
    
    @objc func handleMobileVitalsNotification(notification: Notification) {
        if let cxMobileVitals = notification.object as? CXMobileVitals {
            if cxMobileVitals.type == .metricKit {
                // Send metric as custom error
                
                if let jsonData = cxMobileVitals.value.data(using: .utf8) {
                    do {
                        // Convert JSON data to a dictionary
                        if let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                            self.reportError(message: "metricKit log", data: dictionary)
                        }
                    } catch {
                        Log.w("Error parsing JSON: \(error)")
                    }
                }
            } else {
                let span = self.getMobileVitalsSpan()
                span.setAttribute(key: Keys.mobileVitalsType.rawValue, value: cxMobileVitals.type.rawValue)
                span.setAttribute(key: Keys.mobileVitalsValue.rawValue, value: cxMobileVitals.value)
                span.end()
            }
        }
    }
    
    private func getMobileVitalsSpan() -> Span {
        var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        self.addUserMetadata(to: &span)
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.mobileVitals.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        return span
    }
}
