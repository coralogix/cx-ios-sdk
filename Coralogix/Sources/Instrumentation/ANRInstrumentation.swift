//
//  ANRInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 17/09/2024.
//

import Foundation
import OpenTelemetryApi

extension CoralogixRum {
    
    func initializeANRInstrumentation() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleErrorNotification(notification:)),
                                               name: .cxRumNotificationMetrics, object: nil)
        
    }
    
    @objc func handleErrorNotification(notification: Notification) {
        if let cxMobileVitals = notification.object as? CXMobileVitals {
            if cxMobileVitals.type == .anr {
                let span = self.getSpan()
                span.setAttribute(key: Keys.mobileVitalsType.rawValue, value: cxMobileVitals.type.rawValue)
                span.setAttribute(key: Keys.errorMessage.rawValue, value: Keys.anr.rawValue)
                span.end()
            }
        }
    }
    
    private func getSpan() -> any Span {
        var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.error.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.error.rawValue))
        self.addUserMetadata(to: &span)
        self.addSnapshotContext(to: &span)
        return span
    }
    
    private func addSnapshotContext(to span: inout any Span) {
        self.sessionManager.incrementErrorCounter()
        let snapshot = SnapshotConext(timestemp: Date().timeIntervalSince1970,
                                      errorCount: self.sessionManager.getErrorCount(),
                                      viewCount: self.viewManager.getUniqueViewCount(),
                                      clickCount: self.sessionManager.getClickCount())
        let dict = Helper.convertDictionary(snapshot.getDictionary())
        span.setAttribute(key: Keys.snapshotContext.rawValue,
                          value: Helper.convertDictionayToJsonString(dict: dict))
    }
}
