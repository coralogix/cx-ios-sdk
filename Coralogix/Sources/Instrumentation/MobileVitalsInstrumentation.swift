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
        guard let mobileVitals = notification.object as? MobileVitals else { return }
        
        switch mobileVitals.type {
        case .metricKit:
            if let metric = mobileVitals.name {
                handleMetricKit(metric)
            }
        default:
            handleMobileVitals(mobileVitals)
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
}
