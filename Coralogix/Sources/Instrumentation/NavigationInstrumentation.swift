//
//  NavigationInstrumentation.swift
//
//
//  Created by Coralogix Dev Team on 18/06/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension CoralogixRum {
    public func initializeNavigationInstrumentation() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleNotification(notification:)),
                                               name: .cxRumNotification, object: nil)
    }
    
    @objc func handleNotification(notification: Notification) {
        if let cxView = notification.object as? CXView {
            if viewManager.isUniqueView(name: cxView.name) {
                let span = self.getNavigationSpan()

                let snapshot = SnapshotConext(timestemp: Date().timeIntervalSince1970,
                                              errorCount: self.sessionManager.getErrorCount(),
                                              viewCount: self.viewManager.getUniqueViewCount() + 1,
                                              clickCount: self.sessionManager.getClickCount())
                let dict = Helper.convertDictionary(snapshot.getDictionary())
                span.setAttribute(key: Keys.snapshotContext.rawValue,
                                  value: Helper.convertDictionayToJsonString(dict: dict))
                self.coralogixExporter.set(cxView: cxView)
                span.end()
            } else {
                self.coralogixExporter.set(cxView: cxView)
            }
        } else {
            Log.e("Notification received with no object or with a different object type")
        }
    }
    
    private func getNavigationSpan() -> Span {
        let span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.navigation.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        span.setAttribute(key: Keys.userId.rawValue, value: self.coralogixExporter.getOptions().userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: self.coralogixExporter.getOptions().userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: self.coralogixExporter.getOptions().userContext?.userEmail ?? "" )
        span.setAttribute(key: Keys.environment.rawValue, value: self.coralogixExporter.getOptions().environment )
        return span
    }
}
