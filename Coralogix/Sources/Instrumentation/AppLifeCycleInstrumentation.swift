//
//  AppLifeCycleInstrumentation.swift
//
//
//  Created by Coralogix Dev TEAM on 29/09/2024.
//

#if canImport(UIKit)
import UIKit
#endif

extension CoralogixRum {
    public func initializeAppLifeCycleInstrumentation() {
        if self.options.shouldInitInstumentation(instumentation: .appLifeCycle) {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(appDidFinishLaunching),
                                                   name: UIApplication.didFinishLaunchingNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(appDidBecomeActiveNotification),
                                                   name: UIApplication.didBecomeActiveNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(appDidEnterBackgroundNotification),
                                                   name: UIApplication.didEnterBackgroundNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(appWillTerminateNotification),
                                                   name: UIApplication.willTerminateNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(appDidReceiveMemoryWarningNotification),
                                                   name: UIApplication.didReceiveMemoryWarningNotification,
                                                   object: nil)
        }
    }
    
    @objc private func appDidFinishLaunching(notification: Notification) {
        if self.options.shouldInitInstumentation(instumentation: .appLifeCycle) {
            self.log(severity: .info, message: Keys.appDidFinishLaunching.rawValue)
        }
    }
    
    @objc private func appDidBecomeActiveNotification(notification: Notification) {
        if self.options.shouldInitInstumentation(instumentation: .appLifeCycle) {
            self.log(severity: .info, message: Keys.appDidBecomeActiveNotification.rawValue)
        }
    }
    
    @objc private func appDidEnterBackgroundNotification(notification: Notification) {
        if self.options.shouldInitInstumentation(instumentation: .appLifeCycle) {
            self.log(severity: .info, message: Keys.appDidEnterBackgroundNotification.rawValue)
        }
    }
    
    @objc private func appWillTerminateNotification(notification: Notification) {
        if self.options.shouldInitInstumentation(instumentation: .appLifeCycle) {
            self.log(severity: .info, message: Keys.appWillTerminateNotification.rawValue)
        }
    }
    
    @objc private func appDidReceiveMemoryWarningNotification(notification: Notification) {
        if self.options.shouldInitInstumentation(instumentation: .appLifeCycle) {
            self.log(severity: .info, message: Keys.appDidReceiveMemoryWarningNotification.rawValue)
        }
    }
}
