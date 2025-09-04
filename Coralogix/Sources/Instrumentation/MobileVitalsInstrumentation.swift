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
    
    func handleMobileVitals(_ mobileVitals: MobileVitals) {
        self.mobileVitalHandlers?(mobileVitals)

        let span = self.getSpan(for: mobileVitals)
        let value = self.getMobileVitalsTypeString(mobileVitals.type)
        
        span.setAttribute(key: Keys.mobileVitalsType.rawValue, value: value)
        
        for (key, value) in mobileVitals.type.specificAttributes(for: mobileVitals.value) {
            span.setAttribute(key: key, value: value)
        }
        
        if let name = mobileVitals.name, !name.isEmpty {
            span.setAttribute(key: Keys.name.rawValue, value: name)
        }
        
        span.setAttribute(key: Keys.mobileVitalsUnits.rawValue, value: mobileVitals.units.stringValue)
        
        if let uuid = mobileVitals.uuid, !uuid.isEmpty {
            span.setAttribute(key: Keys.mobileVitalsUuid.rawValue, value: uuid)
        }
        span.end()
    }
    
    func getSpan(for vitals: MobileVitals) -> any Span {
        var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        
        for (key, value) in vitals.type.spanAttributes {
            span.setAttribute(key: key, value: value)
        }
        
        self.addUserMetadata(to: &span)
        return span
    }
    
    func getMobileVitalsTypeString(_ type: MobileVitalsType) -> String {
        switch type {
        case .memoryUtilization, .residentMemory, .footprintMemory:
            return Keys.memory.rawValue
        case .cpuUsage, .mainThreadCpuTime, .totalCpuTime:
            return Keys.cpu.rawValue
        default :
            return type.stringValue
        }
    }
}
