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
        self.metricsManager.addMetricKitObservers()
        self.metricsManager.startMonitoring(using: self.options )
    }
    
    public func initializeANRInstrumentation() {
        self.metricsManager.startANRMonitoring()
    }
    
    func sendMobileVitals(_ mobileVitals: [String: Any]) {
        let span = makeSpan(event: .mobileVitals, source: .code, severity: .info)
        span.setAttribute(key: Keys.mobileVitalsType.rawValue, value: Helper.convertDictionayToJsonString(dict: mobileVitals))
        span.end()
    }
}
