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
        var span = makeSpan(event: .userInteraction, source: .console, severity: .info)
        handleUserInteractionEvent(tapObject, span: &span)
    }
    
    // Handle the case where x and y coordinates are present
    internal func handleUserInteractionEvent(_ properties: [String: Any],
                                             span: inout any Span,
                                             window: UIWindow? = Global.getKeyWindow()) {
       
        if let sessionReplay = SdkManager.shared.getSessionReplay(),
           let screenshotLocation = self.coralogixExporter?.getScreenshotManager().nextScreenshotLocation {
            // Don't capture screenshot here - let SessionReplay capture it
            // so that mask regions (e.g., Flutter widgets) are applied
            let metadata = buildMetadata(properties: properties,
                                         screenshotLocation: screenshotLocation)
            let result = sessionReplay.captureEvent(properties: metadata)
            switch result {
            case .success:
                self.applyScreenshotAttributes(screenshotLocation, to: &span)
            case .failure(let error):
                if error == .skippingEvent {
                    self.coralogixExporter?.getScreenshotManager().revertScreenshotCounter()
                }
            }
        }
        
        span.setAttribute(
            key: Keys.tapObject.rawValue,
            value: Helper.convertDictionayToJsonString(dict: properties)
        )
        span.end()
    }
    
    internal func buildMetadata(properties: [String: Any],
                                screenshotLocation: ScreenshotLocation) -> [String: Any] {
        var metadata = screenshotLocation.toProperties()
        metadata.merge(properties) { current, _ in current } // keep SDK value
        return metadata
    }
    
    // Check if the dictionary contains x and y properties
    internal func containsXY(_ dict: [String: Any]) -> Bool {
        return dict[Keys.positionX.rawValue] != nil && dict[Keys.positionY.rawValue] != nil
    }
}
