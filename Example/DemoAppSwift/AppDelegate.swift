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
@main

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Enable test logger for UI tests
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            Log.enableTestLogging()
            Log.testLog("🧪 Test mode enabled - logging to /tmp/coralogix_test_logs.txt")
            print("🧪 Test mode enabled - Test logging writing to /tmp/coralogix_test_logs.txt")
        }
        #endif

        CoralogixRumManager.shared.initialize()

        // BUGV2-6045 leak-harness mode: when launched with --leak-harness,
        // SessionReplay uses maskAllTexts and auto-starts recording.
        // --leak-harness-60fps switches captureTimeInterval to 1/60 s.
        // For normal launches, SR is initialized with demo defaults so the
        // Start/Stop Recording buttons in SessionReplayViewController work.
        let srOptions: SessionReplayOptions
        if ProcessInfo.processInfo.arguments.contains("--leak-harness") {
            let is60fps = ProcessInfo.processInfo.arguments.contains("--leak-harness-60fps")
            srOptions = SessionReplayOptions(
                recordingType: .image,
                captureTimeInterval: is60fps ? (1.0 / 60.0) : 1.0,
                captureScale: 1.0,
                captureCompressionQuality: 1.0,
                sessionRecordingSampleRate: 100,
                maskAllTexts: true,
                maskOnlyCreditCards: false,
                maskAllImages: false,
                autoStartSessionRecording: true
            )
        } else {
            srOptions = SessionReplayOptions(
                recordingType: .image,
                captureTimeInterval: 10.0,
                captureScale: 2.0,
                captureCompressionQuality: 0.8,
                maskAllTexts: false,
                maskOnlyCreditCards: false,
                maskAllImages: false,
                autoStartSessionRecording: false
            )
        }
        SessionReplay.initializeWithOptions(sessionReplayOptions: srOptions)

        // Only configure Firebase if GoogleService-Info.plist exists and is valid.
        // Skipped in leak-harness mode because the harness uses a stub plist
        // that doesn't pass Firebase's API-key validation; the harness doesn't
        // exercise Firebase anyway.
        let isLeakHarness = ProcessInfo.processInfo.arguments.contains("--leak-harness")
        if !isLeakHarness,
           let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           FileManager.default.fileExists(atPath: path) {
            FirebaseApp.configure()
        } else if !isLeakHarness {
            print("⚠️ Firebase not configured: GoogleService-Info.plist not found (this is expected in CI)")
        }

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
