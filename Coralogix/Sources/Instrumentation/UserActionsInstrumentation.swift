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
        userActionsDelegates = UserActionsDelegates(shouldSendText: options?.shouldSendText,
                                                    resolveTargetName: options?.resolveTargetName)

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
                                                         shouldSendText: userActionsDelegates?.shouldSendText,
                                                         resolveTargetName: userActionsDelegates?.resolveTargetName))
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

    // MARK: - Hybrid User Interaction API

    /// Implementation called by `CoralogixRum.setUserInteraction(_:)`.
    /// Validates the dictionary from the hybrid bridge, then builds a `.userInteraction`
    /// span and enriches it with user / environment context before handing off to
    /// `handleUserInteractionEvent`, which serialises the payload and closes the span.
    internal func reportHybridUserInteraction(_ dictionary: [String: Any]) {
        guard let validated = validateHybridInteraction(dictionary) else { return }

        var span = makeSpan(event: .userInteraction, source: .console, severity: .info)

        // Attach user and environment context, matching the enrichment applied to network spans.
        if let options = coralogixExporter?.getOptions() {
            let userContext = options.userContext
            span.setAttribute(key: Keys.userId.rawValue, value: userContext?.userId ?? "")
            span.setAttribute(key: Keys.userName.rawValue, value: userContext?.userName ?? "")
            span.setAttribute(key: Keys.userEmail.rawValue, value: userContext?.userEmail ?? "")
            span.setAttribute(key: Keys.environment.rawValue, value: options.environment)
        }

        handleUserInteractionEvent(validated, span: &span)
    }

    /// Validates a dictionary received from a hybrid bridge before it is written into a span.
    ///
    /// Returns the (possibly sanitised) dictionary on success, or `nil` when a required
    /// field is missing or carries an unrecognised value — in which case a warning is logged
    /// and the caller must drop the event.
    private func validateHybridInteraction(_ dictionary: [String: Any]) -> [String: Any]? {
        // event_name is required and must be a known InteractionEventName value.
        guard let rawEventName = dictionary[Keys.eventName.rawValue] as? String else {
            Log.w("setUserInteraction: missing required key '\(Keys.eventName.rawValue)' — event dropped")
            return nil
        }
        guard InteractionEventName(rawValue: rawEventName) != nil else {
            Log.w("setUserInteraction: unknown event_name '\(rawEventName)' (expected: click | scroll | swipe) — event dropped")
            return nil
        }

        // target_element is required.
        guard let targetElement = dictionary[Keys.targetElement.rawValue] as? String,
              !targetElement.isEmpty else {
            Log.w("setUserInteraction: missing required key '\(Keys.targetElement.rawValue)' — event dropped")
            return nil
        }

        // scroll_direction, when present, must be a known ScrollDirection value.
        if let rawDirection = dictionary[Keys.scrollDirection.rawValue] as? String,
           ScrollDirection(rawValue: rawDirection) == nil {
            Log.w("setUserInteraction: unknown scroll_direction '\(rawDirection)' (expected: up | down | left | right) — field ignored")
            var sanitised = dictionary
            sanitised.removeValue(forKey: Keys.scrollDirection.rawValue)
            return sanitised
        }

        return dictionary
    }
}
