//
//  Swizzle.swift
//
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

import UIKit

extension UIViewController {
    
    static let swizzleViewDidAppear: Void = {
        let originalSelector = #selector(viewDidAppear(_:))
        let swizzledSelector = #selector(swizzled_viewDidAppear(_:))
        
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector) else { return }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()
    
    static let swizzleViewDidDisappear: Void = {
        let originalSelector = #selector(viewDidDisappear(_:))
        let swizzledSelector = #selector(swizzled_viewDidDisappear(_:))
        
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector) else { return }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()
    
    // Call this method to perform the swizzling
    static func performSwizzling() {
        _ = UIViewController.swizzleViewDidAppear
        _ = UIViewController.swizzleViewDidDisappear
    }
    
    // This method will replace viewDidAppear
    @objc func swizzled_viewDidAppear(_ animated: Bool) {
        updateCoralogixRum(window: self.getWindow(), state: .notifyOnAppear)

        // Call the original implementation
        self.swizzled_viewDidAppear(animated)
    }
    
    @objc func swizzled_viewDidDisappear(_ animated: Bool) {
        updateCoralogixRum(window: self.getWindow(), state: .notifyOnDisappear)

        // Call the original implementation
        self.swizzled_viewDidDisappear(animated)
    }
    
    var viewControllerName: String {
        return String(describing: type(of: self))
    }
    
    func getWindow() -> UIWindow? {
        if #available(iOS 15.0, *) {
            // For iOS 15 and later, handle multiple scenes and the active window
            return UIApplication.shared.connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
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

extension UIWindow {
    /// Returns the top most view controller from given window's root view controller
    func visibleViewController() -> UIViewController? {
        return UIWindow.getVisibleViewControllerFrom(rootViewController: self.rootViewController)
    }

    private static func getVisibleViewControllerFrom(rootViewController: UIViewController?) -> UIViewController? {
        if let navigationController = rootViewController as? UINavigationController {
            return getVisibleViewControllerFrom(rootViewController: navigationController.visibleViewController)
        } else if let tabBarController = rootViewController as? UITabBarController {
            return getVisibleViewControllerFrom(rootViewController: tabBarController.selectedViewController)
        } else if let presentedViewController = rootViewController?.presentedViewController {
            return getVisibleViewControllerFrom(rootViewController: presentedViewController)
        } else {
            return rootViewController
        }
    }
}
