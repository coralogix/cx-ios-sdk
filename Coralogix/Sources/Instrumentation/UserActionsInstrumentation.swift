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

        // The window walk is only worth paying for when this dictionary becomes a span.
        // When no span is emitted (hybrid, or userActions off) it only feeds session
        // replay, the masking flag goes unused, and the hybrid span resolves its own
        // geometry in validateHybridInteraction — walking here too would cost React
        // Native and Flutter apps two full view-tree walks per tap.
        //
        // This now walks whether or not session replay is in use — the geometry is `cxMask`,
        // which is ours, not the replay's. Apps without session replay previously paid nothing
        // here; they now pay one cxMask walk per tap, which is the price of the verdict no
        // longer depending on session replay being initialized. Taps are human-paced, so the
        // walk is not on a hot enough path to warrant caching or a global "any mask set" flag.
        let maskRects: [CGRect]? = shouldEmitUserActionSpan ? UIView.deliberateMaskRects() : nil

        processInteractionEvent(TapDataExtractor.extract(from: touchEvent,
                                                         shouldSendText: userActionsDelegates?.shouldSendText,
                                                         resolveTargetName: userActionsDelegates?.resolveTargetName,
                                                         maskRects: maskRects))
    }

    private func processInteractionEvent(_ properties: [String: Any]) {
        if shouldEmitUserActionSpan {
            let span = makeSpan(event: .userInteraction, source: .console, severity: .info)
            handleUserInteractionEvent(properties, span: span)
        } else {
            // Hybrid or userActions disabled: still feed session replay from native touches.
            captureSessionReplayEventIfNeeded(properties)
        }
    }

    /// When true, native touch events produce RUM user_interaction spans.
    /// When false (hybrid or instrumentations[.userActions] == false), we still install swizzles
    /// so session replay can capture clicks; we just don't emit spans (hybrid uses setUserInteraction).
    /// - Note: `internal` for unit testing.
    internal var shouldEmitUserActionSpan: Bool {
        Helper.shouldEmitUserActionSpan(options: coralogixExporter?.getOptions(), sdkFramework: CoralogixRum.mobileSDK.sdkFramework)
    }

    /// Feeds session replay with interaction metadata (screenshot + properties). No RUM span.
    /// Used when native touch is detected but we are not emitting a user action span (hybrid or userActions off).
    /// With no span to stamp there is nothing to wait for — the model hands the screenshot index
    /// back on its own if the frame is dropped.
    private func captureSessionReplayEventIfNeeded(_ properties: [String: Any]) {
        guard let sessionReplay = SdkManager.shared.getSessionReplay(),
              let screenshotManager = coralogixExporter?.getScreenshotManager() else { return }
        let metadata = buildMetadata(properties: properties,
                                     screenshotLocation: screenshotManager.nextScreenshotLocation)
        _ = sessionReplay.captureEvent(properties: metadata)
    }

    /// The interaction is reported whether or not a frame shipped — only the screenshot attributes
    /// are conditional, and the span closes once the capture resolves. Matches Android, where a
    /// dropped frame yields a null screenshot context and the span is emitted without one.
    internal func handleUserInteractionEvent(_ properties: [String: Any],
                                             span: any Span,
                                             window: UIWindow? = Global.getKeyWindow()) {
        span.setAttribute(
            key: Keys.tapObject.rawValue,
            value: Helper.convertDictionaryToJsonString(dict: properties)
        )
        recordScreenshotForSpan(on: span, extraProperties: properties) { _ in span.end() }
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
    /// span (user/environment context is added by makeSpan via addUserMetadata) and
    /// hands off to `handleUserInteractionEvent`, which serialises the payload and closes the span.
    internal func reportHybridUserInteraction(_ dictionary: [String: Any]) {
        // Masking resolution walks UIKit windows, so it needs the main thread. Bridge calls
        // (React Native modules, Flutter channels) often arrive off-main; hop asynchronously
        // rather than sync-blocking the bridge thread. Main-thread callers stay synchronous.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.reportHybridUserInteraction(dictionary)
            }
            return
        }
        guard let validated = validateHybridInteraction(dictionary) else { return }

        let span = makeSpan(event: .userInteraction, source: .console, severity: .info)
        handleUserInteractionEvent(validated, span: span)
    }

    /// Validates a dictionary received from a hybrid bridge before it is written into a span.
    ///
    /// Returns the (possibly sanitised) dictionary on success, or `nil` when a required
    /// field is missing or carries an unrecognised value — in which case a warning is logged
    /// and the caller must drop the event.
    ///
    /// - Note: `internal` visibility to allow unit testing.
    /// - Parameter maskRects: Deliberate-masking geometry for the masking resolution; nil
    ///   (the production default) resolves it from the view hierarchy via
    ///   `UIView.deliberateMaskRects`, and only once the payload is known to need it.
    ///   Session replay is not consulted — the geometry is `cxMask`, not the replay's
    ///   pixel policy.
    internal func validateHybridInteraction(_ dictionary: [String: Any],
                                            maskRects: [CGRect]? = nil) -> [String: Any]? {
        // event_name is required and must be a known InteractionEventName value.
        guard let rawEventName = dictionary[Keys.eventName.rawValue] as? String else {
            Log.w("setUserInteraction: missing required key '\(Keys.eventName.rawValue)' — event dropped")
            return nil
        }
        guard InteractionEventName(rawValue: rawEventName) != nil else {
            Log.w("setUserInteraction: unknown event_name '\(rawEventName)' (expected: click | scroll | swipe) — event dropped")
            return nil
        }

        // target_element is required and must be a non-empty string (after trimming whitespace and newlines).
        guard let targetElement = dictionary[Keys.targetElement.rawValue] as? String else {
            Log.w("setUserInteraction: missing required key '\(Keys.targetElement.rawValue)' — event dropped")
            return nil
        }
        let trimmed = targetElement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.w("setUserInteraction: missing required key '\(Keys.targetElement.rawValue)' — event dropped")
            return nil
        }

        // Build payload with all supported interaction_context keys so Flutter/hybrid fields are forwarded.
        var result: [String: Any] = [
            Keys.eventName.rawValue: rawEventName,
            Keys.targetElement.rawValue: trimmed
        ]
        if let v = dictionary[Keys.elementClasses.rawValue] { result[Keys.elementClasses.rawValue] = v }
        if let v = dictionary[Keys.elementId.rawValue] { result[Keys.elementId.rawValue] = v }
        if let v = dictionary[Keys.targetElementInnerText.rawValue] { result[Keys.targetElementInnerText.rawValue] = v }
        if let v = dictionary[Keys.attributes.rawValue] { result[Keys.attributes.rawValue] = Self.attributesWithRoundedCoordinates(v, depth: 0, maxDepth: 10) }
        if let v = dictionary[Keys.positionX.rawValue] { result[Keys.positionX.rawValue] = Self.roundCoordinateForRum(v) }
        if let v = dictionary[Keys.positionY.rawValue] { result[Keys.positionY.rawValue] = Self.roundCoordinateForRum(v) }
        // The tap's own time, in epoch seconds. Forwarded verbatim — it reaches the capture, not
        // the span, and tells a Flutter bitmap provider how old the tap already is so Dart can
        // decline to draw one it is too late to represent. Without it a bridge-reported tap asks
        // Dart to hold a frame with no age to judge it against, and the capture waits out its
        // watchdog. Nothing is synthesised when the bridge sends none: no value means no
        // staleness check, which beats guessing at one.
        if let v = dictionary[Keys.tapTimestamp.rawValue] { result[Keys.tapTimestamp.rawValue] = v }

        // scroll_direction: include only when present and a known ScrollDirection value.
        let scrollKey = Keys.scrollDirection.rawValue
        if let rawDirection = dictionary[scrollKey] as? String,
           ScrollDirection(rawValue: rawDirection) != nil {
            result[scrollKey] = rawDirection
        } else if dictionary[scrollKey] != nil, let rawDirection = dictionary[scrollKey] as? String {
            Log.w("setUserInteraction: unknown scroll_direction '\(rawDirection)' (expected: up | down | left | right) — field ignored")
        }

        // A hybrid-reported interaction is redacted on the same terms as a native one: the
        // bridge payload's text is copied verbatim above, so a masked element's real text
        // would otherwise ship (the swizzles feed session replay in hybrid mode, but the span
        // comes from here and never passes through TapDataExtractor). nil = unresolvable →
        // the documented `false` default: the flag under-reports rather than over-reports.
        let isMaskedElement = Self.resolveHybridMasking(dictionary, maskRects: maskRects)
        if let text = result[Keys.targetElementInnerText.rawValue] {
            result[Keys.targetElementInnerText.rawValue] =
                TapDataExtractor.redactIfMasked(text, isMasked: isMaskedElement == true)
        }
        result[Keys.isMaskedElement.rawValue] = isMaskedElement ?? false

        return result
    }

    /// Resolves whether a hybrid-reported interaction targeted masked content.
    ///
    /// Precedence: the wrapper's own verdict (`is_masked` in the bridge dictionary) —
    /// authoritative for hybrids that own their masking (Flutter sets it; React Native does
    /// not) — then the payload's coordinates tested against the deliberate-masking geometry
    /// (`UIView.deliberateMaskRects`), which excludes the replay's pixel policy. Hybrid
    /// coordinates and iOS mask rects are both in points — no unit conversion, unlike Android
    /// where the payload is dp and the rects are px.
    ///
    /// Returns nil when neither is resolvable — no coordinates (React Native scroll and swipe
    /// carry none) or no mask geometry to test against.
    ///
    /// `maskRects` nil means "resolve it here". The resolution deliberately sits below both
    /// early exits: the two commonest hybrid events take them — Flutter always sends
    /// `is_masked`, and React Native scroll and swipe carry no coordinates — so a walk paid
    /// before them would be thrown away on the SDK's highest-frequency hybrid path.
    internal static func resolveHybridMasking(_ dictionary: [String: Any],
                                              maskRects: [CGRect]?) -> Bool? {
        if let verdict = dictionary[Keys.isMasked.rawValue] as? Bool { return verdict }
        guard let x = doubleValue(dictionary[Keys.positionX.rawValue]),
              let y = doubleValue(dictionary[Keys.positionY.rawValue]) else { return nil }
        guard let rects = maskRects ?? UIView.deliberateMaskRects() else { return nil }
        return TapDataExtractor.pointIsMasked(CGPoint(x: x, y: y), in: rects)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return (value as? NSNumber)?.doubleValue
    }

    /// Rounds a numeric coordinate to 2 decimal places for RUM (e.g. 62.04064556 → 62.04). Returns value unchanged if not numeric.
    private static func roundCoordinateForRum(_ value: Any) -> Any {
        guard let double = value as? Double else {
            if let int = value as? Int { return Global.roundToTwoDecimals(CGFloat(int)) }
            if let n = value as? NSNumber { return Global.roundToTwoDecimals(CGFloat(n.doubleValue)) }
            return value
        }
        return Global.roundToTwoDecimals(CGFloat(double))
    }

    /// If value is [String: Any], returns a copy with "x" and "y" (positionX/positionY) rounded to 2 decimals at this level and in any nested [String: Any]; otherwise returns value as-is.
    /// Recursion is capped at `maxDepth` to avoid stack overflow on deeply nested input.
    private static func attributesWithRoundedCoordinates(_ value: Any, depth: Int, maxDepth: Int) -> Any {
        guard let dict = value as? [String: Any] else { return value }
        if depth >= maxDepth { return value }
        var out: [String: Any] = [:]
        for (key, val) in dict {
            if let nested = val as? [String: Any] {
                out[key] = attributesWithRoundedCoordinates(nested, depth: depth + 1, maxDepth: maxDepth)
            } else {
                out[key] = val
            }
        }
        if let x = out[Keys.positionX.rawValue] { out[Keys.positionX.rawValue] = roundCoordinateForRum(x) }
        if let y = out[Keys.positionY.rawValue] { out[Keys.positionY.rawValue] = roundCoordinateForRum(y) }
        return out
    }
}
