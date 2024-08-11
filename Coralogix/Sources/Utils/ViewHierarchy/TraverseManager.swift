//
//  TraverseManager.swift
//
//
//  Created by Coralogix DEV TEAM on 25/07/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension CoralogixRum {
    public func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }
    
    @objc private func appWillEnterForeground() {
        // Handle the app entering the foreground
        Log.d("App will enter foreground")
    }
    
    @objc private func appDidBecomeActive() {
        // Handle the app becoming active
        Log.d("App did become active")
        self.startCXTraverse()
    }
    
    private func startCXTraverse() {
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                // Now you have access to the main UIWindow
                Log.d("\(window)")
                let rootViewController = rootViewControllerFrom(window: window)
                Log.d("\(rootViewController)")
            }
        } else {
            //            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
            //               let window = appDelegate.window {
            //                // Access the window for non-scene based applications
            //                print(window)
            //            }
        }
    }
    
    private func rootViewControllerFrom(window: UIWindow) -> UIViewController? {
        let rootViewController = window.rootViewController
        if let rootViewController = rootViewController {
            // We might be covered by a modal view controller (recursively, so find the last one).
            var presented = rootViewController.presentedViewController
            
            while presented != nil {
                presented = presented?.presentedViewController
            }
            
            if let presented = presented {
                return presented
            } else {
                return rootViewController
            }
        }
        return nil
    }
}
