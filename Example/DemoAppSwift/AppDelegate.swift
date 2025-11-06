//
//  AppDelegate.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

import UIKit
import Coralogix
import SessionReplay
@main

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        CoralogixRumManager.shared.initialize()

        // Must be initialized after CoralogixRum
        let sessionReplayOptions = SessionReplayOptions(recordingType: .image,
                                                        captureTimeInterval: 10.0,
                                                        captureScale: 2.0,
                                                        captureCompressionQuality: 0.8,
                                                        maskText: [],
                                                        maskOnlyCreditCards: false,
                                                        maskAllImages: false,
                                                        autoStartSessionRecording: true)
        SessionReplay.initializeWithOptions(sessionReplayOptions:sessionReplayOptions)
        return true
    }
    
    // MARK: UISceneSession Lifecycle
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

