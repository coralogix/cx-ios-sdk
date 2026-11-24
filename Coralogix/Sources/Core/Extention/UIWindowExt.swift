//
//  UIWindowExt.swift
//
//
//  Created by Coralogix Dev Team on 20/08/2024.
//
import UIKit

public extension UIWindow {
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
