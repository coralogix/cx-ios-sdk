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
        // Install touch-event swizzles only when userActions is enabled.
        // These are no-ops if called more than once (static let guarantees single execution).
        UIApplication.swizzleTouchesEnded
        UIApplication.swizzleSendEvent
        UIApplication.swizzleSwipeGestureRecognizer

        // Cache the closures once here so handleInteractionNotification does not
        // copy the CoralogixExporterOptions struct on every tap event.
        let options = coralogixExporter?.getOptions()
        cachedShouldSendText = options?.shouldSendText
        cachedResolveTargetName = options?.resolveTargetName

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleInteractionNotification(notification:)),
                                               name: .cxRumNotificationUserActions, object: nil)
    }

    @objc func handleInteractionNotification(notification: Notification) {
        guard let touchEvent = notification.object as? TouchEvent else {
            Log.e("Notification received with no TouchEvent object")
            return
        }

        processInteractionEvent(TapDataExtractor.extract(from: touchEvent,
                                                         shouldSendText: cachedShouldSendText,
                                                         resolveTargetName: cachedResolveTargetName))
    }

    private func processInteractionEvent(_ properties: [String: Any]) {
        var span = makeSpan(event: .userInteraction, source: .console, severity: .info)
        handleUserInteractionEvent(properties, span: &span)
    }
    
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
    
    internal func containsXY(_ dict: [String: Any]) -> Bool {
        return dict[Keys.positionX.rawValue] != nil && dict[Keys.positionY.rawValue] != nil
    }
}
