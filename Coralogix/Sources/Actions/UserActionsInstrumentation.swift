//
//  UserActionsInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 23/07/2024.
//

#if canImport(UIKit)
import UIKit
#endif

extension CoralogixRum {
    public func initializeUserActionsInstrumentation() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTapNotification(notification:)),
                                               name: .cxRumNotificationUserActions, object: nil)
    }
    
    @objc func handleTapNotification(notification: Notification) {
        if let tapObject = notification.object as? [String: Any] {
            self.sessionManager.incrementClickCounter()
            let span = self.getUserActionsSpan()
            span.setAttribute(key: Keys.tapObject.rawValue, value: Helper.convertDictionayToJsonString(dict: tapObject))
            span.end()
        } else {
            Log.e("Notification received with no object or with a different object type")
        }
    }
    
    private func getUserActionsSpan() -> Span {
        let span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        let options = self.coralogixExporter.getOptions()
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.userInteraction.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        span.setAttribute(key: Keys.userId.rawValue, value: options.userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: options.userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: options.userContext?.userEmail ?? "" )
        span.setAttribute(key: Keys.environment.rawValue, value: options.environment )
        return span
    }
}
