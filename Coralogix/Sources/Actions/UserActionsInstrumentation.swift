//
//  UserActionsInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 23/07/2024.
//

#if canImport(UIKit)
import UIKit
#endif
import CoralogixInternal

extension CoralogixRum {
    public func initializeUserActionsInstrumentation() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTapNotification(notification:)),
                                               name: .cxRumNotificationUserActions, object: nil)
        
    }
    
    @objc func handleTapNotification(notification: Notification) {
        guard let tapObject = notification.object as? [String: Any] else {
            Log.e("Notification received with no object or with a different object type")
            return
        }
        
        processTapObject(tapObject)
    }
    
    // Increment the click counter and handle the tap object
    private func processTapObject(_ tapObject: [String: Any]) {
        self.sessionManager?.incrementClickCounter()
        
        if containsXY(tapObject) {
            handleSessionReplayEvent(tapObject)
        } else {
            handleNonXYEvent(tapObject)
        }
    }
    
    // Handle the case where x and y coordinates are present
    private func handleSessionReplayEvent(_ tapObject: [String: Any]) {
        if let sessionReplay = SdkManager.shared.getSessionReplay() {
            sessionReplay.captureEvent(properties: tapObject)
        } else {
            Log.e("[SessionReplay] is not initialized")
        }
    }

    // Handle the case where x and y coordinates are not present
    private func handleNonXYEvent(_ tapObject: [String: Any]) {
        let span = getUserActionsSpan()
        span.setAttribute(
            key: Keys.tapObject.rawValue,
            value: Helper.convertDictionayToJsonString(dict: tapObject)
        )
        span.end()
    }
    
    // Check if the dictionary contains x and y properties
    private func containsXY(_ dict: [String: Any]) -> Bool {
        return dict[Keys.positionX.rawValue] != nil && dict[Keys.positionY.rawValue] != nil
    }
    
    private func getUserActionsSpan() -> any Span {
        var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        self.addUserMetadata(to: &span)
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.userInteraction.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        return span
    }
}
