//
//  TapDataExtractor.swift
//
//
//  Created by Coralogix DEV TEAM on 05/02/2025.
//

#if canImport(UIKit)
import UIKit
#endif
import CoralogixInternal

// MARK: - TouchEvent

/// Carries the raw UIKit touch objects and resolved interaction type
/// from the swizzle layer to the instrumentation layer.
struct TouchEvent {
    let view: UIView
    let touch: UITouch?       // nil when the event originates from a gesture recogniser
    let location: CGPoint     // screen-coordinate position (top-left origin)
    let eventType: InteractionEventName
    let scrollDirection: ScrollDirection?
    /// When the touch happened, in epoch seconds. Session replay hands this to the Flutter
    /// bitmap provider so Dart can refuse to draw a tap it can no longer represent honestly,
    /// which only works if the value is the touch's own time rather than the capture's.
    let timestamp: TimeInterval

    /// Standard init — position is derived from the live UITouch (tap / scroll path).
    init(view: UIView,
         touch: UITouch,
         eventType: InteractionEventName = .click,
         scrollDirection: ScrollDirection? = nil) {
        self.view = view
        self.touch = touch
        self.location = touch.location(in: nil)
        self.eventType = eventType
        self.scrollDirection = scrollDirection
        self.timestamp = Self.epochSeconds(ofTouchAt: touch.timestamp)
    }

    /// Gesture-recogniser init — no live UITouch available (swipe path), so the recogniser's
    /// firing time is the closest thing to the touch's own.
    init(view: UIView,
         location: CGPoint,
         eventType: InteractionEventName,
         scrollDirection: ScrollDirection? = nil) {
        self.view = view
        self.touch = nil
        self.location = location
        self.eventType = eventType
        self.scrollDirection = scrollDirection
        self.timestamp = Date().timeIntervalSince1970
    }

    /// `UITouch.timestamp` is seconds since boot, not since the epoch, so it has to be rebased
    /// against the current uptime rather than used directly.
    internal static func epochSeconds(ofTouchAt touchUptime: TimeInterval) -> TimeInterval {
        let age = ProcessInfo.processInfo.systemUptime - touchUptime
        return Date().timeIntervalSince1970 - max(0, age)
    }
}

// MARK: - ScrollTracker

/// Tracks touch state to distinguish taps from scrolls and determine scroll direction.
/// All methods must be called on the main thread (UIKit events are always on the main thread).
///
/// Key design decision: UIScrollView / UITableView gesture recognizers *cancel* the touch
/// (`.cancelled` phase) instead of ending it (`.ended`) when they take over scrolling.
/// At `.cancelled` time, `touch.view` is already nil. We therefore store both the originating
/// view and the latest position on every `.moved` call so `processCancelled` has everything it
/// needs without touching `UITouch` state that UIKit has already invalidated.
final class ScrollTracker {
    static let shared = ScrollTracker()

    /// Minimum movement in points to classify a regular scroll rather than a tap.
    static let threshold: CGFloat = 20.0
    /// Lower threshold used for paged scroll views: a fast page-flip flick covers less
    /// distance than a deliberate drag, but the intent is unambiguous.
    static let pagedThreshold: CGFloat = 5.0

    private struct TouchState {
        let view: UIView
        let start: CGPoint
        var current: CGPoint
        /// Set to `true` on the first `.moved` update.
        /// Used by `processCancelled` to decide whether `state.current` is a real
        /// finger position or just the `.began` snapshot repeated.
        var hasMoved: Bool = false
    }

    private var touchStates: [ObjectIdentifier: TouchState] = [:]

    func recordBegan(_ touch: UITouch, view: UIView) {
        guard Thread.isMainThread else {
            Log.w("ScrollTracker.recordBegan called off the main thread — event ignored")
            return
        }
        let loc = touch.location(in: nil)
        touchStates[ObjectIdentifier(touch)] = TouchState(view: view, start: loc, current: loc)
    }

    /// Must be called on every `.moved` event so `processCancelled` has an up-to-date position.
    func recordMoved(_ touch: UITouch) {
        guard Thread.isMainThread else {
            Log.w("ScrollTracker.recordMoved called off the main thread — event ignored")
            return
        }
        let id = ObjectIdentifier(touch)
        guard touchStates[id] != nil else { return }
        touchStates[id]?.current = touch.location(in: nil)
        touchStates[id]?.hasMoved = true
    }

    /// Shared return envelope used by both `processEnded` and `processCancelled`.
    struct GestureResult {
        let view: UIView
        let direction: ScrollDirection
        /// Resolved event type — `.swipe` for discrete page-flip gestures,
        /// `.scroll` for continuous content scrolling.
        let eventType: InteractionEventName
    }

    /// Return type for `processEnded` and `processCancelled`.
    /// UIKit clears `touch.view` after delivering terminal touch phases, so both paths
    /// use the view stored at `.began` time rather than reading `touch.view` at call time.
    enum EndedGesture {
        case scroll(GestureResult)
        case tap(view: UIView, location: CGPoint)
    }

    /// Alias kept so call sites that use the `.cancelled` name remain readable.
    typealias CancelledGesture = EndedGesture

    /// Returns an `EndedGesture`: `.scroll` if movement exceeded the threshold, `.tap` otherwise.
    ///
    /// Always uses `state.view` (stored at `.began`) as the interaction view because
    /// `touch.view` may be nil by the time `.ended` fires — UIKit can clear the reference
    /// after delivering the event to the responder chain inside the original `sendEvent`.
    ///
    /// For paged scroll views a lower threshold (5 pt) is used because a fast page-flip
    /// flick lifts the finger before `UIPanGestureRecognizer` can formally recognise the
    /// gesture — the displacement at `.ended` time is small even though the intent is clear.
    func processEnded(_ touch: UITouch) -> EndedGesture? {
        guard Thread.isMainThread else {
            Log.w("ScrollTracker.processEnded called off the main thread — event ignored")
            return nil
        }
        guard let state = touchStates.removeValue(forKey: ObjectIdentifier(touch)) else { return nil }
        let nearestScroll = Self.nearestScrollAncestor(state.view)
        let isPaged = nearestScroll?.isPagingEnabled == true
        let threshold: CGFloat = isPaged ? Self.pagedThreshold : Self.threshold
        let endLocation = touch.location(in: nil)
        guard let dir = Self.direction(from: state.start, to: endLocation, threshold: threshold) else {
            return .tap(view: state.view, location: endLocation)
        }
        let eventType: InteractionEventName = isPaged ? .swipe : .scroll
        return .scroll(GestureResult(view: state.view, direction: dir, eventType: eventType))
    }

    /// Called when UIKit cancels a touch because a gesture recogniser took over.
    ///
    /// Prefers `state.current` (last `.moved` snapshot) because it was captured while
    /// `touch.view` was still valid. Falls back to `touch.location(in: nil)` when no `.moved`
    /// events arrived before cancellation — which happens with `UIScrollView.isPagingEnabled`
    /// whose pan recogniser can claim the gesture before the first `.moved` event fires.
    /// `touch.location(in: nil)` returns window-relative coordinates and is valid at `.cancelled`
    /// time because it does not depend on `touch.view`.
    func processCancelled(_ touch: UITouch) -> CancelledGesture? {
        guard Thread.isMainThread else {
            Log.w("ScrollTracker.processCancelled called off the main thread — event ignored")
            return nil
        }
        guard let state = touchStates.removeValue(forKey: ObjectIdentifier(touch)) else { return nil }
        // Prefer the last `.moved` snapshot; fall back to the live location when no `.moved`
        // events arrived before the gesture recogniser cancelled the touch.
        let endPoint = state.hasMoved ? state.current : touch.location(in: nil)
        // Use `pagedThreshold` (5 pt) for all cancelled touches, not just paged ones.
        // Rationale: any gesture recogniser cancelling a touch has already validated the
        // gesture intent against its own (typically 10-20 pt) recognition threshold.
        // By the time `.cancelled` arrives, our recorded displacement may be smaller than
        // the actual finger movement because `.moved` events can lag behind recognition.
        // 5 pt is always less than any recogniser's own threshold, so it never fires
        // for accidental micro-movements that a recogniser would have rejected.
        guard let dir = Self.direction(from: state.start, to: endPoint,
                                       threshold: Self.pagedThreshold) else {
            // Below threshold — the touch was a tap on a control whose gesture recogniser
            // cancelled delivery (UINavigationBar, UITabBar, UIToolbar, etc.).
            // Return the stored view and tap location so the caller can emit a click event.
            return .tap(view: state.view, location: endPoint)
        }
        let isPaged = Self.nearestScrollAncestor(state.view)?.isPagingEnabled == true
        let eventType: InteractionEventName = isPaged ? .swipe : .scroll
        return .scroll(GestureResult(view: state.view, direction: dir, eventType: eventType))
    }

    /// Walks the view hierarchy upward and returns the first `UIScrollView` ancestor
    /// (including `view` itself if it is a `UIScrollView`), or `nil` if none exists.
    ///
    /// Stopping at the **nearest** scroll ancestor ensures consistent behaviour in nested
    /// hierarchies: a touch inside a `UITableView` that is itself inside a paged scroll view
    /// is governed by the table — not the outer pager — because the table is the scroll view
    /// that actually received the gesture.  Both the displacement threshold and the event type
    /// (`.swipe` vs `.scroll`) are derived from the same `isPagingEnabled` flag on this one
    /// ancestor, guaranteeing the two decisions are always in sync.
    private static func nearestScrollAncestor(_ view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let v = current {
            if let sv = v as? UIScrollView { return sv }
            current = v.superview
        }
        return nil
    }

    /// Pure direction resolver — separated for testability.
    /// Returns `nil` when the delta is below `threshold` (tap, not scroll).
    static func direction(from start: CGPoint,
                          to end: CGPoint,
                          threshold: CGFloat = ScrollTracker.threshold) -> ScrollDirection? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard abs(dx) >= threshold || abs(dy) >= threshold else { return nil }
        return abs(dy) >= abs(dx)
            ? (dy < 0 ? .up : .down)
            : (dx < 0 ? .left : .right)
    }

    /// Removes a touch from tracking without emitting any event.
    /// Call this when a swipe gesture recogniser on a non-scroll view has already claimed the
    /// gesture — prevents `processCancelled` from also firing a redundant event.
    func discardTouch(_ touch: UITouch) {
        guard Thread.isMainThread else {
            Log.w("ScrollTracker.discardTouch called off the main thread — event ignored")
            return
        }
        touchStates.removeValue(forKey: ObjectIdentifier(touch))
    }
}

// MARK: - TapDataExtractor

/// Extracts a structured tap-data dictionary from a resolved touch event.
/// This is the single place that knows how to map UIKit view metadata
/// to the interaction_context schema.
enum TapDataExtractor {
    /// - Parameter shouldSendText: Optional delegate from `CoralogixExporterOptions`.
    ///   When provided, it is called with the view and candidate text before recording
    ///   `target_element_inner_text`. Return `false` to redact the text to `***` — the key is
    ///   still reported, so a redacted tap stays distinguishable from one on an element with no
    ///   text. Views that are already masked never reach this delegate and their text is never
    ///   passed to it; see the redaction rules at the call site below.
    /// - Parameter resolveTargetName: Optional delegate from `CoralogixExporterOptions`.
    ///   When provided, its return value replaces the UIKit class name in `target_element`.
    ///   Returning `nil` falls back to the resolved class name.
    /// - Parameter maskRects: The deliberate-masking geometry (screen points) from
    ///   `UIView.deliberateMaskRects` — `cxMask` only, with the replay's pixel policy
    ///   excluded. The caller resolves it, and decides whether the walk is worth paying for
    ///   at all (see `handleInteractionNotification`). nil when unresolvable or skipped —
    ///   geometry then contributes nothing to the masking decision.
    static func extract(from event: TouchEvent,
                        shouldSendText: ((UIView, String) -> Bool)? = nil,
                        resolveTargetName: ((UIView) -> String?)? = nil,
                        maskRects: [CGRect]? = nil) -> [String: Any] {
        var tapData = [String: Any]()
        let view = event.view

        tapData[Keys.eventName.rawValue] = event.eventType.rawValue

        // Masked = deliberate-masking geometry (needed for SwiftUI `.cxMask()`, which overlays
        // a masked sibling the view tree cannot see) unioned with the view-tree walk, which
        // still answers when no geometry is available, and the PII traits, which cover secure
        // fields that paint no rect.
        //
        // The replay's pixel policy (maskText / maskAllImages) is deliberately not an input:
        // it answers whether pixels should be hidden in a frame, not whether text may leave
        // the device. So this flag and the replay's tap-marker suppression can legitimately
        // disagree for policy-masked content — matching Android and Flutter.
        let isMaskedElement = (maskRects.map { pointIsMasked(event.location, in: $0) } ?? false)
            || view.isInsideMaskedSubtree
            || hasSensitivePIIProperties(view)
        tapData[Keys.isMaskedElement.rawValue] = isMaskedElement

        // element_classes always reflects the true UIKit class name — never overridden.
        // target_element can be customised via resolveTargetName; falls back to class name.
        let resolvedClassName = resolveClassName(NSStringFromClass(type(of: view)))
        tapData[Keys.elementClasses.rawValue] = resolvedClassName
        tapData[Keys.targetElement.rawValue]  = resolveTargetName?(view) ?? resolvedClassName

        // element_id: accessibility identifier set by the developer
        if let accessibilityId = view.accessibilityIdentifier, !accessibilityId.isEmpty {
            tapData[Keys.elementId.rawValue] = accessibilityId
        }

        // target_element_inner_text: redacted text, never omitted text.
        // Container views are skipped (they span many items; text would be ambiguous), and a view
        // with no text at all reports nothing. Everything else reports either its text or `***`,
        // so a masked tap is visibly masked rather than indistinguishable from a tap on something
        // that had nothing to say. Matches the Android SDK.
        //
        // Text is redacted when the masking decision above says the tap targeted masked
        // content, or when the caller's shouldSendText delegate rejects it. The delegate is
        // consulted last and only for text that is not already redacted — a password must not
        // reach the customer's closure. The delegate's rejection redacts the text but does not
        // set `is_masked_element`: the flag records what session replay masked, not what the
        // customer's reporting gate withheld.
        if !isContainerView(resolvedClassName),
           let innerText = rawInnerText(from: view),
           !innerText.isEmpty {
            let isAllowedByDelegate = !isMaskedElement && (shouldSendText?(view, innerText) ?? true)
            tapData[Keys.targetElementInnerText.rawValue] =
                redactIfMasked(innerText, isMasked: isMaskedElement || !isAllowedByDelegate)
        }

        // scroll_direction: only present for scroll/swipe events
        if let direction = event.scrollDirection {
            tapData[Keys.scrollDirection.rawValue] = direction.rawValue
        }

        // x/y coordinates are stored both in tapData root (session replay compatibility)
        // and in the nested attributes dict (interaction_context schema).
        // On key collision, the incoming value wins — attributes data overrides earlier values.
        var attributes = [String: Any]()
        Global.updateLocation(tapData: &attributes, location: event.location)
        tapData.merge(attributes) { _, new in new }
        tapData[Keys.tapTimestamp.rawValue] = event.timestamp
        tapData[Keys.attributes.rawValue] = attributes

        return tapData
    }

    /// The one redaction rule, shared by the native path above and the hybrid path
    /// (`validateHybridInteraction`) so the two cannot drift: masked text is replaced by
    /// `***`, never omitted, keeping a masked tap distinguishable from a tap on an element
    /// with no text. Only `target_element_inner_text` is redacted — identity fields and
    /// coordinates ship as-is (web-SDK parity; stricter policies belong to the customer's
    /// `beforeSend`, keyed on `is_masked_element`).
    static func redactIfMasked(_ innerText: Any, isMasked: Bool) -> Any {
        isMasked ? Keys.maskedInnerText.rawValue : innerText
    }

    /// Whether a tap at `point` (screen points) landed inside one of the given masked regions.
    /// Same test mechanics as the replay's tap-marker suppression (`ScannerPipeline.containsTap`),
    /// including failing closed on overlapping windows — but applied to different geometry: the
    /// marker tests the rects the frame actually painted, this tests deliberate masking only.
    static func pointIsMasked(_ point: CGPoint, in maskRects: [CGRect]) -> Bool {
        maskRects.contains { $0.contains(point) }
    }

    /// Container views that span multiple content items — extracting inner text from them
    /// would return text from an arbitrary child (e.g. the last visible cell), not the tapped item.
    private static let containerClasses: Set<String> = [
        "UITableView", "UIScrollView", "UICollectionView",
        "UINavigationBar", "UITabBar", "UIWindow", "UIView"
    ]

    private static func isContainerView(_ resolvedClassName: String) -> Bool {
        return containerClasses.contains(resolvedClassName)
    }

    /// `UITextContentType` values that unambiguously signal sensitive PII.
    /// Any input view whose `textContentType` is in this set is suppressed regardless of class.
    private static let sensitiveContentTypes: Set<UITextContentType> = [
        .password,
        .newPassword,
        .creditCardNumber,
    ]

    /// Returns `true` when the view carries iOS system properties that explicitly flag it as
    /// holding sensitive PII — a password mask or a sensitive `textContentType`.
    /// This is intentionally checked via `UITextInputTraits` so it applies uniformly to
    /// `UITextField`, `UITextView`, and `UISearchBar` without repeating logic per class.
    static func hasSensitivePIIProperties(_ view: UIView) -> Bool {
        guard let traits = view as? UITextInputTraits else { return false }
        if traits.isSecureTextEntry == true { return true }
        if let contentType = traits.textContentType.flatMap({ $0 }),
           sensitiveContentTypes.contains(contentType) { return true }
        return false
    }

    /// Returns the text a tapped view displays, whether or not it is sensitive.
    ///
    /// **Text extraction:**
    /// - `UITextField` / `UITextView` / `UISearchBar` → current text
    /// - `UIButton`           → button title
    /// - `UILabel`            → label text
    /// - `UITableViewCell`    → `UIListContentConfiguration.text` (iOS 14+), else `textLabel`
    /// - `UISegmentedControl` → currently selected segment title
    /// - `UIDatePicker`, `UIStepper` → no text property; fall through to `accessibilityLabel`
    ///
    /// **Fallback:** `accessibilityLabel` — always developer-set, never user-typed.
    ///
    /// Deliberately does **not** apply the sensitive-PII block, so a caller can tell "this view
    /// has sensitive text" apart from "this view has no text" — a distinction that matters once
    /// the answer is redaction to `***` rather than omission. Pair it with
    /// `hasSensitivePIIProperties` before reporting anything.
    ///
    /// Callers take on the obligation not to let the value escape: it may be a password. Report
    /// `Keys.maskedInnerText` in its place, and never hand it to a customer callback.
    static func rawInnerText(from view: UIView) -> String? {
        // --- Text input views (non-sensitive) ---
        if let textField = view as? UITextField {
            return textField.text
        }
        if let textView = view as? UITextView {
            let text = textView.text ?? ""
            return text.isEmpty ? nil : text
        }
        if let searchBar = view as? UISearchBar {
            return searchBar.text
        }

        // --- Developer-authored text ---
        if let button = view as? UIButton {
            return button.title(for: .normal)
        }
        if let label = view as? UILabel {
            return label.text
        }
        if let cell = view as? UITableViewCell {
            // iOS 14+: prefer UIListContentConfiguration (the modern cell config API).
            // textLabel is deprecated in iOS 14 and is nil for cells configured this way.
            if #available(iOS 14.0, *),
               let config = cell.contentConfiguration as? UIListContentConfiguration {
                // Only return when we have a genuinely non-empty string.
                // An empty config.text must not short-circuit the accessibilityLabel fallback.
                let candidate = [config.text, config.secondaryText]
                    .compactMap { $0 }
                    .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if let candidate { return candidate }
                // fall through to accessibilityLabel
            } else if let text = cell.textLabel?.text,
                      !text.trimmingCharacters(in: .whitespaces).isEmpty {
                return text
            }
        }
        if let segment = view as? UISegmentedControl {
            let idx = segment.selectedSegmentIndex
            guard idx != UISegmentedControl.noSegment else { return nil }
            return segment.titleForSegment(at: idx)
        }

        // --- Fallback: accessibility label (developer-set, never user-typed) ---
        return view.accessibilityLabel
    }

    /// Maps internal UIKit private subclass names to their canonical public class name.
    /// e.g. "UITableViewCellContentView" → "UITableViewCell", "_UIPageIndicatorView" → "UIPageIndicatorView".
    /// Falls through to the bare (module-prefix-stripped) class name for all other views.
    ///
    /// Uses `hasPrefix` on the bare class name (module prefix stripped) so that a third-party
    /// class like "SomeSDKUITableViewProxy" does NOT accidentally match "UITableView".
    static func resolveClassName(_ className: String) -> String {
        // Strip module prefix: "MyModule.UITableView" → "UITableView"
        let bare = className.components(separatedBy: ".").last ?? className

        // More specific prefixes must be checked before their shorter superstrings.
        if bare.hasPrefix("UITableViewCellContentView") { return "UITableViewCell" }
        if bare.hasPrefix("_UIPageIndicatorView")       { return "UIPageIndicatorView" }
        if bare.hasPrefix("UITabBarButton")             { return "UITabBarButton" }
        if bare.hasPrefix("UITableViewCell")            { return "UITableViewCell" }
        if bare.hasPrefix("UICollectionViewCell")       { return "UICollectionViewCell" }
        if bare.hasPrefix("UICollectionView")           { return "UICollectionView" }
        if bare.hasPrefix("UITableView")                { return "UITableView" }
        return bare
    }
}
