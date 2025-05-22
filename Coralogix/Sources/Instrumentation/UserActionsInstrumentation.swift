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
    internal func handleUserInteractionEvent(_ properties: [String: Any],
                                             span: any Span,
                                             window: UIWindow? = Global.getKeyWindow()) {
        let timestamp = Date().timeIntervalSince1970
        let screenshotId = UUID().uuidString.lowercased()

        if let sessionReplay = SdkManager.shared.getSessionReplay(),
           containsXY(properties) {
            
            guard let window = window else {
                Log.e("No key window found")
                return
            }
            
            guard let screenshotData = window.captureScreenshot() else {
                Log.e("Failed to capture screenshot")
                return
            }
            
            let metadata = buildMetadata(properties: properties,
                                         timestamp: timestamp,
                                         screenshotId: screenshotId,
                                         screenshotData: screenshotData)
            span.setAttribute(key: Keys.screenshotId.rawValue, value: screenshotId)
            sessionReplay.captureEvent(properties: metadata)
        }
        
        span.setAttribute(
            key: Keys.tapObject.rawValue,
            value: Helper.convertDictionayToJsonString(dict: properties)
        )
        span.end()
    }
    
    internal func buildMetadata(properties: [String: Any],
                                timestamp: TimeInterval,
                                screenshotId: String,
                                screenshotData: Data?) -> [String: Any] {
        var metadata: [String: Any] = [
            Keys.timestamp.rawValue: timestamp,
            Keys.screenshotId.rawValue: screenshotId,
        ]
        
        if screenshotData != nil {
            metadata[Keys.screenshotData.rawValue] =  screenshotData
        }
        // Keep SDK-generated keys if duplicates exist
        metadata.merge(properties) { (_, current) in current }
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
