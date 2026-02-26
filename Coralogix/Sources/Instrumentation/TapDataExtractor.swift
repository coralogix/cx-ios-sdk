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
    let touch: UITouch
    let eventType: InteractionEventName
    let scrollDirection: ScrollDirection?

    init(view: UIView,
         touch: UITouch,
         eventType: InteractionEventName = .click,
         scrollDirection: ScrollDirection? = nil) {
        self.view = view
        self.touch = touch
        self.eventType = eventType
        self.scrollDirection = scrollDirection
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

    /// Minimum movement in points to classify a gesture as a scroll rather than a tap.
    static let threshold: CGFloat = 20.0

    private struct TouchState {
        let view: UIView
        let start: CGPoint
        var current: CGPoint
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
    }

    /// Returns `(view, direction)` if movement exceeded the threshold (scroll), or `nil` (tap).
    func processEnded(_ touch: UITouch) -> (view: UIView, direction: ScrollDirection)? {
        guard Thread.isMainThread else {
            Log.w("ScrollTracker.processEnded called off the main thread — event ignored")
            return nil
        }
        guard let state = touchStates.removeValue(forKey: ObjectIdentifier(touch)) else { return nil }
        guard let dir = direction(from: state.start, to: touch.location(in: nil)) else { return nil }
        return (state.view, dir)
    }

    /// Called when UIKit cancels a touch because a scroll-view gesture recogniser took over.
    /// Uses `state.current` (last `.moved` position) because `touch.view` / `touch.location`
    /// are unreliable at `.cancelled` time.
    func processCancelled(_ touch: UITouch) -> (view: UIView, direction: ScrollDirection)? {
        guard Thread.isMainThread else {
            Log.w("ScrollTracker.processCancelled called off the main thread — event ignored")
            return nil
        }
        guard let state = touchStates.removeValue(forKey: ObjectIdentifier(touch)) else { return nil }
        guard let dir = direction(from: state.start, to: state.current) else { return nil }
        return (state.view, dir)
    }

    /// Pure direction resolver — separated for testability.
    /// Returns `nil` when the delta is below the threshold (tap, not scroll).
    func direction(from start: CGPoint, to end: CGPoint) -> ScrollDirection? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard abs(dx) >= Self.threshold || abs(dy) >= Self.threshold else { return nil }
        return abs(dy) >= abs(dx)
            ? (dy < 0 ? .up : .down)
            : (dx < 0 ? .left : .right)
    }
}

// MARK: - TapDataExtractor

/// Extracts a structured tap-data dictionary from a resolved touch event.
/// This is the single place that knows how to map UIKit view metadata
/// to the interaction_context schema.
enum TapDataExtractor {
    static func extract(from event: TouchEvent) -> [String: Any] {
        var tapData = [String: Any]()
        let view = event.view

        tapData[Keys.eventName.rawValue] = event.eventType.rawValue

        // Both element_classes and target_element start with the same resolved class name.
        // CX-32583 will let users override target_element via resolveTargetName;
        // element_classes always stays as the UIKit class name.
        let resolvedClassName = resolveClassName(NSStringFromClass(type(of: view)))
        tapData[Keys.elementClasses.rawValue] = resolvedClassName
        tapData[Keys.targetElement.rawValue]  = resolvedClassName

        // element_id: accessibility identifier set by the developer
        if let accessibilityId = view.accessibilityIdentifier, !accessibilityId.isEmpty {
            tapData[Keys.elementId.rawValue] = accessibilityId
        }

        // target_element_inner_text: PII-safe text only.
        // Container views are skipped (they span many items; text would be ambiguous).
        // Input views (UITextField, UITextView, UISearchBar) are always skipped —
        // they hold user-typed content which may be passwords, emails, or other PII.
        if !isContainerView(resolvedClassName),
           let innerText = safeInnerText(from: view),
           !innerText.isEmpty {
            tapData[Keys.targetElementInnerText.rawValue] = innerText
        }

        // scroll_direction: only present for scroll/swipe events
        if let direction = event.scrollDirection {
            tapData[Keys.scrollDirection.rawValue] = direction.rawValue
        }

        // x/y coordinates are stored both in tapData root (session replay compatibility)
        // and in the nested attributes dict (interaction_context schema).
        // On key collision, the incoming value wins — attributes data overrides earlier values.
        var attributes = [String: Any]()
        Global.updateLocation(tapData: &attributes, touch: event.touch)
        tapData.merge(attributes) { _, new in new }
        tapData[Keys.attributes.rawValue] = attributes

        return tapData
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
    private static func hasSensitivePIIProperties(_ view: UIView) -> Bool {
        guard let traits = view as? UITextInputTraits else { return false }
        if traits.isSecureTextEntry == true { return true }
        if let contentType = traits.textContentType.flatMap({ $0 }),
           sensitiveContentTypes.contains(contentType) { return true }
        return false
    }

    /// Returns developer-authored or user-typed (non-sensitive) text for a tapped view.
    ///
    /// **Property-based block (always nil — sensitive PII signals present):**
    /// Text input views (`UITextField`, `UITextView`, `UISearchBar`) are blocked when iOS
    /// system properties explicitly mark the field as sensitive:
    /// - `isSecureTextEntry == true` (password / PIN masking)
    /// - `textContentType` is `.password`, `.newPassword`, or `.creditCardNumber`
    ///
    /// **Text extraction (non-sensitive input and developer-authored text):**
    /// - `UITextField` / `UITextView` / `UISearchBar` → current text (if non-sensitive)
    /// - `UIButton`           → button title
    /// - `UILabel`            → label text
    /// - `UITableViewCell`    → `UIListContentConfiguration.text` (iOS 14+), else `textLabel`
    /// - `UISegmentedControl` → currently selected segment title
    /// - `UIDatePicker`, `UIStepper` → no text property; fall through to `accessibilityLabel`
    ///
    /// **Fallback:** `accessibilityLabel` — always developer-set, never user-typed.
    static func safeInnerText(from view: UIView) -> String? {
        // --- Property-based PII block ---
        // Checked before any type-specific extraction so it applies to all input classes.
        if hasSensitivePIIProperties(view) { return nil }

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
                // fall through to accessibilityLabel
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
