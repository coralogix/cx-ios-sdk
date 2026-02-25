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

/// Tracks touch start positions to distinguish taps from scrolls and determine scroll direction.
/// All methods must be called on the main thread (UIKit events are always on the main thread).
final class ScrollTracker {
    static let shared = ScrollTracker()

    /// Minimum movement in points to classify a gesture as a scroll rather than a tap.
    let threshold: CGFloat = 20.0

    private var startLocations: [ObjectIdentifier: CGPoint] = [:]

    func recordBegan(_ touch: UITouch) {
        startLocations[ObjectIdentifier(touch)] = touch.location(in: nil)
    }

    /// Returns the scroll direction if movement exceeded the threshold, or `nil` if it was a tap.
    func processEnded(_ touch: UITouch) -> ScrollDirection? {
        guard let start = startLocations.removeValue(forKey: ObjectIdentifier(touch)) else { return nil }
        return direction(from: start, to: touch.location(in: nil))
    }

    func cancel(_ touch: UITouch) {
        startLocations.removeValue(forKey: ObjectIdentifier(touch))
    }

    /// Pure direction resolver — separated for testability.
    /// Returns `nil` when the delta is below the threshold (i.e. it is a tap, not a scroll).
    func direction(from start: CGPoint, to end: CGPoint) -> ScrollDirection? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard abs(dx) >= threshold || abs(dy) >= threshold else { return nil }
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

        Global.updateLocation(tapData: &tapData, touch: event.touch)

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

        // target_element_inner_text: visible text or accessibility label
        let innerText = Helper.findFirstLabelText(in: view) ?? view.accessibilityLabel
        if let innerText = innerText, !innerText.isEmpty {
            tapData[Keys.targetElementInnerText.rawValue] = innerText
        }

        // scroll_direction: only present for scroll/swipe events
        if let direction = event.scrollDirection {
            tapData[Keys.scrollDirection.rawValue] = direction.rawValue
        }

        return tapData
    }

    /// Maps internal UIKit private subclass names to their canonical public class name.
    /// e.g. "UITableViewCellContentView" → "UITableViewCell", "_UIPageIndicatorView" → "UIPageIndicatorView".
    /// Falls through to the raw class name for all other views.
    static func resolveClassName(_ className: String) -> String {
        if className.contains("UITableViewCellContentView") { return "UITableViewCell" }
        if className.contains("_UIPageIndicatorView")       { return "UIPageIndicatorView" }
        if className.contains("UITabBarButton")             { return "UITabBarButton" }
        if className.contains("UITableViewCell")            { return "UITableViewCell" }
        if className.contains("UICollectionViewCell")       { return "UICollectionViewCell" }
        if className.contains("UICollectionView")           { return "UICollectionView" }
        if className.contains("UITableView")                { return "UITableView" }
        return className
    }
}
