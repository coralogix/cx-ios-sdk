//
//  Swizzle.swift
//
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

// swiftlint:disable file_length

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
    
    static func swizzleInstanceMethod(for cls: AnyClass, originalSelector: Selector, swizzledSelector: Selector) {
        guard let originalMethod = class_getInstanceMethod(cls, originalSelector),
              let swizzledMethod = class_getInstanceMethod(cls, swizzledSelector) else {
            Log.e("Failed to swizzle \(originalSelector)")
            return
        }
        
        let originalIMP = method_getImplementation(originalMethod)
        let swizzledIMP = method_getImplementation(swizzledMethod)
        
        let key = originalSelector
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

extension UICollectionView {
    static let swizzleTouchesEnded: Void = {
        let originalSelector = #selector(UIResponder.touchesEnded(_:with:))
        let swizzledSelector = #selector(cx_touchesEnded(_:with:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UICollectionView.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    @objc func cx_touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            self.cx_touchesEnded(touches, with: event) // Call original method
            return
        }
        
        let location = touch.location(in: self)
        guard let indexPath = self.indexPathForItem(at: location),
              let cell = self.cellForItem(at: indexPath) else {
            self.cx_touchesEnded(touches, with: event) // Call original method
            return
        }
        
        let attributes: [String: Any] = [
            Keys.text.rawValue: Helper.findFirstLabelText(in: cell) ?? ""
        ]
        
        let tapData: [String: Any] = [
            Keys.tapName.rawValue: "UICollectionView.didSelectRowAt",
            Keys.tapCount.rawValue: 1,
            Keys.tapAttributes.rawValue: attributes
        ]
        
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tapData)
        
        self.cx_touchesEnded(touches, with: event) // Call original method
    }
}

extension UITableView {
    static let swizzleTouchesEnded: Void = {
        let originalSelector = #selector(UITableView.touchesEnded(_:with:))
        let swizzledSelector = #selector(cx_touchesEnded(_:with:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UITableView.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    @objc func cx_touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            self.cx_touchesEnded(touches, with: event) // Call original method
            return
        }
        
        let location = touch.location(in: self)
        guard let indexPath = self.indexPathForRow(at: location),
              let cell = self.cellForRow(at: indexPath) else {
            self.cx_touchesEnded(touches, with: event) // Call original method
            return
        }
        
        let attributes: [String: Any] = [
            Keys.text.rawValue: Helper.findFirstLabelText(in: cell) ?? ""
        ]
        
        let tapData: [String: Any] = [
            Keys.tapName.rawValue: "UITableView.didSelectRowAt",
            Keys.tapCount.rawValue: 1,
            Keys.tapAttributes.rawValue: attributes
        ]
        
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tapData)
        
        self.cx_touchesEnded(touches, with: event) // Call original method
    }
}

extension UITableViewController {
    static let swizzleUITableViewControllerDelegate: Void = {
        let originalSelector = #selector(UITableViewController.tableView(_:didSelectRowAt:))
        let swizzledSelector = #selector(cx_tableView(_:didSelectRowAt:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UITableViewController.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    @objc func cx_tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.cx_tableView(tableView, didSelectRowAt: indexPath)
        
        if let cell = tableView.cellForRow(at: indexPath) {
            var attributes = [String: Any]()
            attributes[Keys.text.rawValue] = cell.textLabel?.text ?? ""
            
            let tap = [Keys.tapName.rawValue: "UITableView.didSelectRowAt",
                       Keys.tapCount.rawValue: 1,
                       Keys.tapAttributes.rawValue: attributes] as [String: Any]
            NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
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

extension UIPageControl {
    static let swizzleSetCurrentPage: Void = {
        let originalSelector = #selector(setter: currentPage)
        let swizzledSelector = #selector(cx_setCurrentPage(_:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UIPageControl.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    @objc private func cx_setCurrentPage(_ page: Int) {
        self.cx_setCurrentPage(page)
        
        let tap = [Keys.tapName.rawValue: "UIPageController",
                   Keys.tapCount.rawValue: 1,
                   Keys.tapAttributes.rawValue: Helper.convertDictionayToJsonString(dict: [:])] as [String: Any]
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
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
    
    public static let swizzleSendAction: Void = {
        let originalSelector = #selector(UIApplication.sendAction(_:to:from:for:))
        let swizzledSelector = #selector(cx_sendAction(_:to:from:for:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UIApplication.self,
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
        if let touches = event.allTouches, let touch = touches.first, touch.phase == .began {
            let location = touch.location(in: nil) // Screen coordinates
            let positionX = location.x
            let positionY = location.y
            
            // Post the touch event to a notification center or your SDK
            let tap = [Keys.positionX.rawValue: positionX,
                       Keys.positionY.rawValue: positionY] as? [String: Any]
            NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
        }
    }
    
    @objc private func cx_sendAction(_ action: Selector,
                                     to target: AnyObject?,
                                     from sender: AnyObject?,
                                     for event: UIEvent?) -> Bool {
        let selectorNameCString = sel_getName(action)
        let selectorNameString = String(cString: selectorNameCString)
        if selectorNameString.contains("tabBarItemClicked") {
            self.handleTabBarItemClicked(sender: sender)
        } else if selectorNameString.contains("backButtonAction") {
            self.handleBackButtonAction(sender: sender)
        } else if selectorNameString.contains("segmentChanged") {
            self.handleSegmentChanged(sender: sender)
        } else if selectorNameString.contains("buttonDown") {
            self.handleButtonDown(sender: sender, target: target)
        } else if selectorNameString.contains("dismissViewController") {
            self.handleDismissViewController(sender: sender)
        }
        
        return cx_sendAction(action, to: target, from: sender, for: event)
    }
    
    private func handleDismissViewController(sender: AnyObject?) {
        guard let sender = sender else { return }
        let senderClass = NSStringFromClass(type(of: sender))
        var attributes = [String: Any]()
        if let button = sender as? UIButton {
            attributes[Keys.text.rawValue] = button.titleLabel?.text
        }
        
        let tap = [Keys.tapName.rawValue: "\(senderClass)",
                   Keys.tapCount.rawValue: 1,
                   Keys.tapAttributes.rawValue: Helper.convertDictionayToJsonString(dict: attributes)] as [String: Any]
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
    }
    
    private func handleTabBarItemClicked(sender: AnyObject?) {
        guard let sender = sender else { return }
        let senderClass = NSStringFromClass(type(of: sender))
        var attributes = [String: Any]()
        if let description = sender.description,
           let title = ViewHelper.extractTitleUITabBarItem(from: description) {
            attributes[Keys.text.rawValue] = title
        }
        let tap = [Keys.tapName.rawValue: "\(senderClass)",
                   Keys.tapCount.rawValue: 1,
                   Keys.tapAttributes.rawValue: Helper.convertDictionayToJsonString(dict: attributes)] as [String: Any]
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
    }
    
    private func handleBackButtonAction(sender: AnyObject?) {
        if sender != nil {
            let tap = [Keys.tapName.rawValue: "backButton",
                       Keys.tapCount.rawValue: 1,
                       Keys.tapAttributes.rawValue: [:]] as [String: Any]
            NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
        }
    }
    
    private func handleSegmentChanged(sender: AnyObject?) {
        guard let sender = sender, let segmentedControl = sender as? UISegmentedControl else { return }
        var attributes = [String: Any]()
        let selectedIndex = segmentedControl.selectedSegmentIndex
        let selectedTitle = segmentedControl.titleForSegment(at: selectedIndex)
        attributes[Keys.text.rawValue] = "\(selectedTitle ?? "None")"
        let tap = [Keys.tapName.rawValue: "UISegmentedControl",
                   Keys.tapCount.rawValue: 1,
                   Keys.tapAttributes.rawValue: Helper.convertDictionayToJsonString(dict: attributes)] as [String: Any]
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
    }
    
    private func handleButtonDown(sender: AnyObject?, target: AnyObject?) {
        guard let sender = sender else { return }
        var attributes = [String: Any]()
        if let tabBar = target as? UITabBar {
            attributes[Keys.text.rawValue] = tabBar.selectedItem?.title
        }
        let senderClass = NSStringFromClass(type(of: sender))
        let tap = [Keys.tapName.rawValue: "\(senderClass)",
                   Keys.tapCount.rawValue: 1,
                   Keys.tapAttributes.rawValue: Helper.convertDictionayToJsonString(dict: attributes)] as [String: Any]
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
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
            
            NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                            object: [Keys.coldEnd.rawValue: CFAbsoluteTimeGetCurrent()])
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
