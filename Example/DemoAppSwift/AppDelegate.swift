//
//  AppDelegate.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

import UIKit
import Coralogix
import SessionReplay
import Firebase
import Sentry
import CloudKit

@main

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Force CloudKit to load for testing UserDefaults corruption bug
        CloudKitTestHelper.forceLoadCloudKit()
        
        SentrySDK.start { options in
            options.dsn = "https://a1981f08beeecc23b04fd02f17a06424@o4510856319205376.ingest.us.sentry.io/4510856320909312"

            // Adds IP for users.
            // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
            options.sendDefaultPii = true

            // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
            // We recommend adjusting this value in production.
            options.tracesSampleRate = 1.0

            // Configure profiling. Visit https://docs.sentry.io/platforms/apple/profiling/ to learn more.
            options.configureProfiling = {
                $0.sessionSampleRate = 1.0 // We recommend adjusting this value in production.
                $0.lifecycle = .trace
            }

            // Uncomment the following lines to add more data to your events
            // options.attachScreenshot = true // This adds a screenshot to the error events
            // options.attachViewHierarchy = true // This adds the view hierarchy to the error events
            
            // Enable experimental logging features
            options.experimental.enableLogs = true
        }
        // Remove the next line after confirming that your Sentry integration is working.
        SentrySDK.capture(message: "This app uses Sentry! :)")


        CoralogixRumManager.shared.initialize()

        // Only configure Firebase if GoogleService-Info.plist exists and is valid
        // This allows the app to run in CI without Firebase
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           FileManager.default.fileExists(atPath: path) {
            FirebaseApp.configure()
        } else {
            print("⚠️ Firebase not configured: GoogleService-Info.plist not found (this is expected in CI)")
        }


//        // Must be initialized after CoralogixRum
//        let sessionReplayOptions = SessionReplayOptions(recordingType: .image,
//                                                        captureTimeInterval: 10.0,
//                                                        captureScale: 2.0,
//                                                        captureCompressionQuality: 0.8,
//                                                        maskText: [],
//                                                        maskOnlyCreditCards: false,
//                                                        maskAllImages: false,
//                                                        autoStartSessionRecording: true)
//        SessionReplay.initializeWithOptions(sessionReplayOptions:sessionReplayOptions)
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
