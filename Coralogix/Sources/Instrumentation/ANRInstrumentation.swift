//
//  ANRInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 13/02/2026.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    /// Initializes ANR (Application Not Responding) detection
    /// ANR events are reported as error events, not mobile vitals
    public func initializeANRInstrumentation() {
        // Set ANR error callback
        self.metricsManager.anrErrorClosure = { [weak self] errorMessage, errorType in
            self?.reportANRError(errorMessage: errorMessage, errorType: errorType)
        }
        self.metricsManager.startANRMonitoring()
    }
    
    /// Reports ANR as an error event
    /// - Parameters:
    ///   - errorMessage: The formatted ANR error message (e.g., "Application Not Responding for at least 5000 ms.")
    ///   - errorType: The error type (always "ANR")
    private func reportANRError(errorMessage: String, errorType: String) {
        var span = makeSpan(event: .error, source: .code, severity: .error)
        span.setAttribute(key: Keys.errorMessage.rawValue, value: errorMessage)
        span.setAttribute(key: Keys.errorType.rawValue, value: errorType)
        
        recordScreenshotForSpan(to: &span)
        span.end()
        
        Log.d("[CoralogixRum] ANR error event sent: \(errorMessage)")
    }
}
