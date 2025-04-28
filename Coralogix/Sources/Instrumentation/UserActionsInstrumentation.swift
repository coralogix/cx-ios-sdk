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
        let span = getUserActionsSpan()
        handleUserInteractionEvent(tapObject, span: span)
    }
    
    // Handle the case where x and y coordinates are present
    internal func handleUserInteractionEvent(_ properties: [String: Any], span: any Span) {
        let timestamp = Date().timeIntervalSince1970
        let screenshotId = UUID().uuidString.lowercased()

        if let sessionReplay = SdkManager.shared.getSessionReplay(),
           containsXY(properties) {
            let metadata = buildMetadata(properties: properties, timestamp: timestamp, screenshotId: screenshotId)
            span.setAttribute(key: Keys.screenshotId.rawValue, value: screenshotId)
            sessionReplay.captureEvent(properties: metadata)
        }
        
        span.setAttribute(
            key: Keys.tapObject.rawValue,
            value: Helper.convertDictionayToJsonString(dict: properties)
        )
        span.end()
    }
    
    internal func buildMetadata(properties: [String: Any], timestamp: TimeInterval, screenshotId: String) -> [String: Any] {
        var metadata: [String: Any] = [
            Keys.timestamp.rawValue: timestamp,
            Keys.screenshotId.rawValue: screenshotId
        ]
        metadata.merge(properties) { (_, new) in new }
        return metadata
    }
    
    // Check if the dictionary contains x and y properties
    internal func containsXY(_ dict: [String: Any]) -> Bool {
        return dict[Keys.positionX.rawValue] != nil && dict[Keys.positionY.rawValue] != nil
    }
    
    internal func getUserActionsSpan() -> any Span {
        var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        self.addUserMetadata(to: &span)
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.userInteraction.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        return span
    }
}
