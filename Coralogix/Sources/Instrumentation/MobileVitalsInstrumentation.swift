//
//  MobileVitalsInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 10/09/2024.
//

import Foundation

extension CoralogixRum {
    public func initializeMobileVitalsInstrumentation() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleMobileVitalsNotification(notification:)),
                                               name: .cxRumNotificationMetrics, object: nil)
    }
    
    @objc func handleMobileVitalsNotification(notification: Notification) {
        guard let cxMobileVitals = notification.object as? CXMobileVitals else { return }
        
        if cxMobileVitals.type == .metricKit {
            handleMetricKit(cxMobileVitals.value)
        } else {
            handleRegularMobileVitals(cxMobileVitals)
        }
    }
    
    private func handleMetricKit(_ value: String) {
        guard let jsonData = value.data(using: .utf8) else { return }
        
        do {
            if let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                reportError(message: "metricKit log", data: dictionary)
            }
        } catch {
            Log.w("Error parsing JSON: \(error)")
        }
    }

    private func handleRegularMobileVitals(_ cxMobileVitals: CXMobileVitals) {
        Log.w("mobile vitals type: \(cxMobileVitals.type.rawValue)")
        let span = getMobileVitalsSpan()
        span.setAttribute(key: Keys.mobileVitalsType.rawValue, value: cxMobileVitals.type.rawValue)
        span.setAttribute(key: Keys.mobileVitalsValue.rawValue, value: cxMobileVitals.value)
        span.end()
    }
    
    private func getMobileVitalsSpan() -> Span {
        var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        self.addUserMetadata(to: &span)
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.mobileVitals.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        return span
    }
}
