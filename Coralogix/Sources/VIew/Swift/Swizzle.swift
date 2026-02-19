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
        // Call the original implementation (swizzled now)
        cx_sendEvent(event)
        
        // Process touch events
        if let touches = event.allTouches,
           let touch = touches.first,
           touch.phase == .began {
            if let view = touch.view {
                var tapData = [String: Any]()
                Global.updateLocation(tapData: &tapData, touch: touch)

                let className = NSStringFromClass(type(of: view))
                if className.contains("UITableViewCellContentView") {
                    tapData[Keys.tapName.rawValue] = "UITableView Cell"
                } else if className.contains("_UIPageIndicatorView") {
                    tapData[Keys.tapName.rawValue] = "UIPageIndicatorView"
                } else if className.contains("UITabBarButton") {
                    tapData[Keys.tapName.rawValue] = "UITabBarButton"
                } else if className.contains("UITableView") {
                    tapData[Keys.tapName.rawValue] = "UITableView"
                } else {
                    Log.w("Unsupported view class: \(className)")
                }
                
                if let labelText = Helper.findFirstLabelText(in: view),
                   let existing = tapData[Keys.tapName.rawValue] as? String {
                    tapData[Keys.tapName.rawValue] = "\(existing.lowercased()) - \(labelText.lowercased())"
                }
                
                NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tapData)
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
            // Call the original viewDidAppear method for UINavigationController
            cx_viewDidAppear(animated)
        } else {
            // Custom implementation for UIViewController
            updateCoralogixRum(window: self.getWindow(), state: .notifyOnAppear)
            
            NotificationCenter.default.post(name: .cxViewDidAppear,
                                            object: [MobileVitalsType.cold.stringValue: CFAbsoluteTimeGetCurrent()])
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
