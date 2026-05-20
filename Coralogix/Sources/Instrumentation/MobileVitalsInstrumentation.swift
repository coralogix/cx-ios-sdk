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
}
