//
//  AppDelegate.swift
//  DemoAppTvOS
//
//  Created by Coralogix Dev Team on 18/08/2024.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        CoralogixRumManager.shared.initialize(application: "DemoApp-tvOS")
        return true
    }
}
