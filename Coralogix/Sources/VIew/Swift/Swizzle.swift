//
//  Swizzle.swift
//
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import CoralogixInternal
import ObjectiveC.runtime

public struct CXView {
    enum AppState: String {
        case notifyOnAppear
        case notifyOnDisappear
    }
    
    let state: AppState
    let name: String
}

class SwizzleUtils {
    /// Composite key that uniquely identifies a (class, selector) pair.
    /// Using only `Selector` as the key is incorrect when the same selector is swizzled
    /// on different classes (e.g. `touchesEnded(_:with:)` on both
    /// `SwiftUI.UIKitGestureRecognizer` and `UISwipeGestureRecognizer`), because the
    /// two entries would share a key and overwrite each other's original IMP.
    private struct SwizzleKey: Hashable {
        let classIdentifier: ObjectIdentifier
        let selector: Selector

        init(cls: AnyClass, selector: Selector) {
            self.classIdentifier = ObjectIdentifier(cls)
            self.selector = selector
        }
    }

    private static var originalImplementations: [SwizzleKey: IMP] = [:]

    // THREAD-SAFE: Lock protects originalImplementations dictionary access
    // CRITICAL: Prevents race conditions when multiple swizzles happen concurrently
    private static let swizzleLock = NSLock()

    static func swizzleInstanceMethod(for cls: AnyClass, originalSelector: Selector, swizzledSelector: Selector) {
        // SAFETY: Wrap entire swizzle operation in lock to prevent TOCTOU race conditions
        swizzleLock.lock()
        defer { swizzleLock.unlock() }

        guard let originalMethod = class_getInstanceMethod(cls, originalSelector),
              let swizzledMethod = class_getInstanceMethod(cls, swizzledSelector) else {
            Log.e("Failed to swizzle \(originalSelector) on \(cls)")
            return // SAFETY: Log error but don't crash host app
        }

        let originalIMP = method_getImplementation(originalMethod)
        let swizzledIMP = method_getImplementation(swizzledMethod)

        // Key combines class identity and selector so two classes swizzling the same
        // selector each get their own entry in originalImplementations.
        let key = SwizzleKey(cls: cls, selector: originalSelector)
        // THREAD-SAFE: Dictionary access protected by lock
        if originalImplementations[key] == nil {
            originalImplementations[key] = originalIMP
        }

        let didAddMethod = class_addMethod(cls,
                                           originalSelector,
                                           swizzledIMP,
                                           method_getTypeEncoding(swizzledMethod))

        if didAddMethod {
            class_replaceMethod(cls,
                                swizzledSelector,
                                originalIMP,
                                method_getTypeEncoding(originalMethod))
        } else {
            let previousIMP = method_getImplementation(originalMethod)
            if previousIMP != originalIMP {
                // Already swizzled by another SDK, chain the implementations
                let block: @convention(block) (Any) -> Void = { obj in
                    let originalIMP = originalImplementations[key] ?? previousIMP
                    typealias Function = @convention(c) (Any, Selector) -> Void
                    let originalMethod = unsafeBitCast(originalIMP, to: Function.self)
                    originalMethod(obj, originalSelector)

                    let swizzledMethod = unsafeBitCast(swizzledIMP, to: Function.self)
                    swizzledMethod(obj, swizzledSelector)
                }

                let newIMP = imp_implementationWithBlock(block)
                method_setImplementation(originalMethod, newIMP)
            } else {
                method_exchangeImplementations(originalMethod, swizzledMethod)
            }
        }
    }
}

extension UIGestureRecognizer {
    @objc func cx_touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.cx_touchesEnded(touches, with: event)
        
        if let touch = touches.first, let view = touch.view, let nextResponder = view.next as? UIView {
            if ViewHelper.isSwiftUIView(view: view) || ViewHelper.isSwiftUIView(view: nextResponder) {
                return
            }
            _ = ViewHelper.cxElementForView(view: view)
        }
    }
}

extension UISwipeGestureRecognizer {
    /// Intercepts swipe gesture completion to emit a `.swipe` interaction event.
    /// Called after the original `touchesEnded`, at which point `state == .recognized`.
    @objc func cx_swipeTouchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cx_swipeTouchesEnded(touches, with: event) // call original — updates recogniser state

        // Only fire when the gesture was actually recognized (discrete recognisers use .recognized == .ended).
        guard state == .recognized,
              let view = self.view,
              touches.count == 1,
              let touch = touches.first else { return }

        // Scroll-view context: let both events fire — .scroll represents content movement,
        // .swipe represents the finger gesture. For all other views, discard the touch from
        // ScrollTracker so the .cancelled phase in cx_sendEvent does not also post a
        // redundant .scroll notification for the same gesture.
        if !isScrollViewContext(view) {
            ScrollTracker.shared.discardTouch(touch)
        }

        // Drop the event if the direction bitmask is ambiguous (empty or multiple bits set).
        guard let scrollDir = cxScrollDirection(from: direction) else { return }

        NotificationCenter.default.post(
            name: .cxRumNotificationUserActions,
            object: TouchEvent(view: view, location: touch.location(in: nil),
                               eventType: .swipe, scrollDirection: scrollDir)
        )
    }

    /// Returns `true` when `view` is, or is embedded inside, a `UIScrollView` (including `UITableView`).
    private func isScrollViewContext(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current {
            if v is UIScrollView { return true }
            current = v.superview
        }
        return false
    }

    /// Maps a `UISwipeGestureRecognizer.Direction` bitmask to our `ScrollDirection` enum.
    ///
    /// Returns `nil` when the bitmask is ambiguous — either empty (no direction configured)
    /// or containing more than one of `.up`, `.down`, `.left`, `.right`.  A multi-direction
    /// recogniser (e.g. `.left | .right`) fires for both swipes but the `direction` property
    /// always reflects the full configured set, so we cannot determine which way the user
    /// actually swiped.  Callers must drop the event when `nil` is returned.
    private func cxScrollDirection(from d: UISwipeGestureRecognizer.Direction) -> ScrollDirection? {
        let candidates: [(UISwipeGestureRecognizer.Direction, ScrollDirection)] = [
            (.up, .up), (.down, .down), (.left, .left), (.right, .right)
        ]
        let matches = candidates.filter { d.contains($0.0) }
        guard matches.count == 1 else {
            Log.w("cxScrollDirection: ambiguous direction bitmask \(d.rawValue) (\(matches.count) matches) — event dropped")
            return nil
        }
        return matches[0].1
    }
}

extension UIApplication {
    public static let swizzleTouchesEnded: Void = {
        guard let targetClass = NSClassFromString("SwiftUI.UIKitGestureRecognizer") else {
            return
        }
        
        let originalSelector = #selector(UIGestureRecognizer.touchesEnded(_:with:))
        let swizzledSelector = #selector(UIGestureRecognizer.cx_touchesEnded(_:with:))
        
        SwizzleUtils.swizzleInstanceMethod(for: targetClass,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    public static let swizzleSendEvent: Void = {
        let originalSelector = #selector(sendEvent(_:))
        let swizzledSelector = #selector(cx_sendEvent(_:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UIApplication.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()

    public static let swizzleSwipeGestureRecognizer: Void = {
        let originalSelector = #selector(UIGestureRecognizer.touchesEnded(_:with:))
        let swizzledSelector = #selector(UISwipeGestureRecognizer.cx_swipeTouchesEnded(_:with:))

        SwizzleUtils.swizzleInstanceMethod(for: UISwipeGestureRecognizer.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    @objc func cx_sendEvent(_ event: UIEvent) {
        cx_sendEvent(event)

        guard let touches = event.allTouches else { return }

        // Interaction events (click / scroll) are only meaningful for single-finger gestures.
        // For multi-touch (pinch, two-finger scroll etc.) we still track every touch so that
        // ScrollTracker.touchStates is fully cleaned up, but we suppress event firing.
        let isSingleTouch = touches.count == 1

        for touch in touches {
            switch touch.phase {
            case .began:
                // Store the originating view — it will be nil by the time .cancelled fires.
                guard let view = touch.view else { continue }
                ScrollTracker.shared.recordBegan(touch, view: view)

            case .moved:
                // Keep current position updated so processCancelled has accurate data.
                ScrollTracker.shared.recordMoved(touch)

            case .ended:
                if let result = ScrollTracker.shared.processEnded(touch), isSingleTouch {
                    NotificationCenter.default.post(
                        name: .cxRumNotificationUserActions,
                        object: TouchEvent(view: result.view, touch: touch, eventType: result.eventType, scrollDirection: result.direction)
                    )
                } else if isSingleTouch {
                    if let view = touch.view {
                        NotificationCenter.default.post(
                            name: .cxRumNotificationUserActions,
                            object: TouchEvent(view: view, touch: touch, eventType: .click)
                        )
                    } else {
                        // touch.view can be nil at .ended if the view was removed from
                        // the hierarchy between .began and .ended (e.g. a modal dismissed
                        // during the gesture). Dropping the tap is the correct behaviour.
                        Log.w("cx_sendEvent .ended: touch.view is nil — tap event dropped")
                    }
                }

            case .cancelled:
                // Gesture recognisers (UIScrollView pan, UIScreenEdgePanGestureRecognizer, etc.)
                // cancel the touch instead of ending it. touch.view is nil here; the view and
                // event type are resolved from the state recorded at .began time.
                if let result = ScrollTracker.shared.processCancelled(touch), isSingleTouch {
                    NotificationCenter.default.post(
                        name: .cxRumNotificationUserActions,
                        object: TouchEvent(view: result.view, touch: touch, eventType: result.eventType, scrollDirection: result.direction)
                    )
                }
                // processCancelled is always called (cleans up touchStates) but no event is posted for multi-touch.

            default:
                break
            }
        }
    }
}

extension UIViewController {
    static let swizzleViewDidAppear: Void = {
        let originalSelector = #selector(viewDidAppear(_:))
        let swizzledSelector = #selector(cx_viewDidAppear(_:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UIViewController.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    static let swizzleViewDidDisappear: Void = {
        let originalSelector = #selector(viewDidDisappear(_:))
        let swizzledSelector = #selector(cx_viewDidDisappear(_:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UIViewController.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    // This method will replace viewDidAppear
    @objc func cx_viewDidAppear(_ animated: Bool) {
        if self.isKind(of: UINavigationController.self) {
            cx_viewDidAppear(animated)
        } else {
            updateCoralogixRum(window: self.getWindow(), state: .notifyOnAppear)
            cx_viewDidAppear(animated)
        }
    }
    
    @objc func cx_viewDidDisappear(_ animated: Bool) {
        updateCoralogixRum(window: self.getWindow(), state: .notifyOnDisappear)
        
        // Call the original implementation
        self.cx_viewDidDisappear(animated)
    }
    
    var viewControllerName: String {
        return String(describing: type(of: self))
    }
    
    func getWindow() -> UIWindow? {
        if #available(iOS 15.0, *) {
            // For iOS 15 and later, handle multiple scenes and the active window
            if let window = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) {
                return window
            }
            
            // Fallback to AppDelegate's window reference if all else fails
            if let appDelegate = UIApplication.shared.delegate {
                return appDelegate.window ?? nil
            }
            
            return nil
        } else {
            // For iOS 13 and 14
            return UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })
        }
    }
}

// MARK: - Helpers

private func updateCoralogixRum(window: UIWindow?, state: CXView.AppState) {
    if !Thread.current.isMainThread {
        return
    }
    
    if let window = window {
        if let viewController = window.visibleViewController() {
            // When loading swiftUI project, we want to ignore "UIHostingController" view
            // due to the fact that swizzlling is always on, and we add view in swiftUI manually.
            if viewController.viewControllerName.contains("UIHostingController") {
                return
            }
            let name = viewController.viewControllerName
            let cxView = CXView(state: state, name: name)
            NotificationCenter.default.post(name: .cxRumNotification, object: cxView)
        }
    }
}
