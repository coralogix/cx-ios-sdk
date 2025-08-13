//
//  MobileVitalsInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 10/09/2024.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    public func initializeMobileVitalsInstrumentation() {
        guard let sessionManager = self.sessionManager,
              !sessionManager.hasInitializedMobileVitals else { return }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleMobileVitalsNotification(notification:)),
                                               name: .cxRumNotificationMetrics, object: nil)
        self.sessionManager?.hasInitializedMobileVitals = true
    }
    
    @objc func handleMobileVitalsNotification(notification: Notification) {
        guard let cxMobileVitals = notification.object as? CXMobileVitals else { return }
        
        switch cxMobileVitals.type {
        case .metricKit:
            handleMetricKit(cxMobileVitals.value)
        default:
            handleMobileVitals(cxMobileVitals)
        }
    }
    
    private func handleMetricKit(_ value: String) {
        guard let jsonData = value.data(using: .utf8) else {
            Log.w("Invalid MetricKit string, cannot convert to data: \(value)")
            return
        }
        
        do {
            if let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                reportError(message: Keys.metricKitLog.rawValue, data: dictionary)
            } else {
                Log.w("MetricKit JSON did not produce a valid dictionary")
            }
        } catch {
            Log.w("Error parsing MetricKit JSON: \(error), original value: \(value)")
        }
    }
    
    private func handleMobileVitals(_ cxMobileVitals: CXMobileVitals) {
        let span = self.getSpan(for: cxMobileVitals)
        span.setAttribute(key: Keys.mobileVitalsType.rawValue, value: cxMobileVitals.type.rawValue)
        
        for (key, value) in cxMobileVitals.type.specificAttributes(for: cxMobileVitals.value) {
            span.setAttribute(key: key, value: value)
        }
        
        if let uuid = cxMobileVitals.uuid, !uuid.isEmpty {
            span.setAttribute(key: Keys.mobileVitalsUuid.rawValue, value: uuid)
        }
        span.end()
    }
    
    private func getSpan(for vitals: CXMobileVitals) -> any Span {
        var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        
        for (key, value) in vitals.type.spanAttributes {
            span.setAttribute(key: key, value: value)
        }
        
        self.addUserMetadata(to: &span)
        return span
    }
}
