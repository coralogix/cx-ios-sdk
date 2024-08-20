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
    static func swizzleInstanceMethod(for cls: AnyClass, originalSelector: Selector, swizzledSelector: Selector) {
        guard let originalMethod = class_getInstanceMethod(cls, originalSelector),
              let swizzledMethod = class_getInstanceMethod(cls, swizzledSelector) else {
            Log.e("failed to swizzleInstanceMethod \(cls)")
            return
        }
        
        let didAddMethod = class_addMethod(cls,
                                           originalSelector,
                                           method_getImplementation(swizzledMethod),
                                           method_getTypeEncoding(swizzledMethod))
        
        if didAddMethod {
            class_replaceMethod(cls,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
}

extension UICollectionView {
    static let swizzleUICollectionViewDelegate: Void = {
        let originalSelector = #selector(setter: UICollectionView.delegate)
        let swizzledSelector = #selector(swizzled_setDelegate(_:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UICollectionView.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    @objc private func swizzled_setDelegate(_ delegate: UICollectionViewDelegate?) {
        // Call the original setDelegate method
        swizzled_setDelegate(delegate)
        
        guard let delegate = delegate else { return }
        
        let originalSelector = #selector(UICollectionViewDelegate.collectionView(_:didSelectItemAt:))
        let swizzledSelector = #selector(UIViewController.swizzled_collectionView(_:didSelectItemAt:))

        if let delegateClass: AnyClass = object_getClass(delegate) {
            SwizzleUtils.swizzleInstanceMethod(for: type(of: delegate),
                                               originalSelector: originalSelector,
                                               swizzledSelector: swizzledSelector)
        }
    }
}

extension UITableView {
    static let swizzleUITableViewDelegate: Void = {
        let originalSelector = #selector(setter: UITableView.delegate)
        let swizzledSelector = #selector(swizzled_setDelegate(_:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UITableView.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    @objc private func swizzled_setDelegate(_ delegate: UITableViewDelegate?) {
        // Call the original setDelegate method
        swizzled_setDelegate(delegate)
        
        guard let delegate = delegate else { return }
        
        if let delegateClass: AnyClass = object_getClass(delegate) {
            let originalSelector = #selector(UITableViewDelegate.tableView(_:didSelectRowAt:))
            let swizzledSelector = #selector(UITableView.swizzled_tableView(_:didSelectRowAt:))
            
            SwizzleUtils.swizzleInstanceMethod(for: delegateClass,
                                               originalSelector: originalSelector,
                                               swizzledSelector: swizzledSelector)
        }
    }
    
    @objc func swizzled_tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Call the original implementation (which is now this method due to swizzling)
        self.swizzled_tableView(tableView, didSelectRowAt: indexPath)
        
        // Your custom implementation
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

extension UITableViewController {
    static let swizzleUITableViewControllerDelegate: Void = {
        let originalSelector = #selector(UITableViewController.tableView(_:didSelectRowAt:))
        let swizzledSelector = #selector(swizzled_tableView(_:didSelectRowAt:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UITableViewController.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    @objc func swizzled_tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.swizzled_tableView(tableView, didSelectRowAt: indexPath)
        
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
            if CXHelper.isSwiftUIView(view: view) || CXHelper.isSwiftUIView(view: nextResponder) {
                return
            }
            let dict = CXHelper.cxElementForView(view: view)
        }
    }
}

extension UIPageControl {
    static let swizzleSetCurrentPage: Void = {
        let originalSelector = #selector(setter: currentPage)
        let swizzledSelector = #selector(swizzled_setCurrentPage(_:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UIPageControl.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    @objc private func swizzled_setCurrentPage(_ page: Int) {
        swizzled_setCurrentPage(page)
        
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
        let swizzledSelector = #selector(UIApplication.cx_sendAction(_:to:from:for:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UIApplication.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
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
           let title = CXHelper.extractTitleUITabBarItem(from: description) {
            attributes[Keys.text.rawValue] = title
        }
        let tap = [Keys.tapName.rawValue: "\(senderClass)",
                   Keys.tapCount.rawValue: 1,
                   Keys.tapAttributes.rawValue: Helper.convertDictionayToJsonString(dict: attributes)] as [String: Any]
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
    }
    
    private func handleBackButtonAction(sender: AnyObject?) {
        guard let sender = sender else { return }
        let tap = [Keys.tapName.rawValue: "backButton",
                   Keys.tapCount.rawValue: 1,
                   Keys.tapAttributes.rawValue: [:]] as [String: Any]
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
    }

    private func handleSegmentChanged(sender: AnyObject?) {
        guard let sender = sender, let segmentedControl = sender as? UISegmentedControl else { return }
        var attributes = [String: Any]()
        let selectedIndex = segmentedControl.selectedSegmentIndex
        let selectedTitle = segmentedControl.titleForSegment(at: selectedIndex)
        attributes[Keys.text.rawValue] = "\(selectedTitle ?? "None")"
        let senderClass = NSStringFromClass(type(of: sender))
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
        let swizzledSelector = #selector(swizzled_viewDidAppear(_:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UIViewController.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    static let swizzleViewDidDisappear: Void = {
        let originalSelector = #selector(viewDidDisappear(_:))
        let swizzledSelector = #selector(swizzled_viewDidDisappear(_:))
        
        SwizzleUtils.swizzleInstanceMethod(for: UIViewController.self,
                                           originalSelector: originalSelector,
                                           swizzledSelector: swizzledSelector)
    }()
    
    // This method will replace viewDidAppear
    @objc func swizzled_viewDidAppear(_ animated: Bool) {
        if self.isKind(of: UINavigationController.self) {
            // Call the original viewDidAppear method for UINavigationController
            swizzled_viewDidAppear(animated)
        } else {
            // Custom implementation for UIViewController
            updateCoralogixRum(window: self.getWindow(), state: .notifyOnAppear)
            
            // Call the original viewDidAppear
            swizzled_viewDidAppear(animated)
        }
    }
    
    @objc func swizzled_viewDidDisappear(_ animated: Bool) {
        updateCoralogixRum(window: self.getWindow(), state: .notifyOnDisappear)
        
        // Call the original implementation
        self.swizzled_viewDidDisappear(animated)
    }
    
    @objc func swizzled_collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        swizzled_collectionView(collectionView, didSelectItemAt: indexPath)
        // Your custom implementation
        if let cell = collectionView.cellForItem(at: indexPath) {
            var attributes = [String: Any]()
            attributes[Keys.text.rawValue] =  Helper.findFirstLabelText(in: cell) ?? ""
            
            let tap = [Keys.tapName.rawValue: "UITableView.didSelectRowAt",
                       Keys.tapCount.rawValue: 1,
                       Keys.tapAttributes.rawValue: attributes] as [String: Any]
            NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
        }
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
        } else if #available(iOS 13.0, *) {
            // For iOS 13 and 14
            return UIApplication.shared.windows.first { $0.isKeyWindow }
        } else {
            // For iOS 12 and earlier
            return UIApplication.shared.keyWindow
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
