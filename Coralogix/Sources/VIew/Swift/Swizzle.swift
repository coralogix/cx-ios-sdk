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
    private static var originalImplementations: [Selector: IMP] = [:]
    
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
        
        let key = originalSelector
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
    
    @objc func cx_sendEvent(_ event: UIEvent) {
        cx_sendEvent(event)

        guard let touches = event.allTouches, let touch = touches.first else { return }

        switch touch.phase {
        case .began:
            // Store the originating view here — it will be nil by the time .cancelled fires.
            guard let view = touch.view else { return }
            ScrollTracker.shared.recordBegan(touch, view: view)

        case .moved:
            // Keep current position updated so processCancelled has accurate data.
            ScrollTracker.shared.recordMoved(touch)

        case .ended:
            if let result = ScrollTracker.shared.processEnded(touch) {
                NotificationCenter.default.post(
                    name: .cxRumNotificationUserActions,
                    object: TouchEvent(view: result.view, touch: touch, eventType: .scroll, scrollDirection: result.direction)
                )
            } else if let view = touch.view {
                NotificationCenter.default.post(
                    name: .cxRumNotificationUserActions,
                    object: TouchEvent(view: view, touch: touch, eventType: .click)
                )
            } else {
                Log.w("cx_sendEvent .ended: touch.view is nil — tap event dropped")
            }

        case .cancelled:
            // UIScrollView / UITableView gesture recognisers cancel touches instead of ending them.
            // touch.view is nil here; we rely on the view stored at .began time.
            if let result = ScrollTracker.shared.processCancelled(touch) {
                NotificationCenter.default.post(
                    name: .cxRumNotificationUserActions,
                    object: TouchEvent(view: result.view, touch: touch, eventType: .scroll, scrollDirection: result.direction)
                )
            }
            // If processCancelled returns nil the movement was below threshold (cancelled tap) — discard.

        default:
            break
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
            // Call the original viewDidAppear method for UINavigationController
            cx_viewDidAppear(animated)
        } else {
            // Custom implementation for UIViewController
            updateCoralogixRum(window: self.getWindow(), state: .notifyOnAppear)
            // Call the original viewDidAppear
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
