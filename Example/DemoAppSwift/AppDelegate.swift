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
    static var coralogixRum: CoralogixRum? = nil
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        let userContext = UserContext(userId: "ww",
                                      userName: "?",
                                      userEmail: "a@a.com",
                                      userMetadata: ["d":"d"])
        let options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.STG,
                                               userContext: userContext,
                                               environment: "PROD",
                                               application: "",
                                               version: "1",
                                               publicKey: "",
                                               instrumentations: [.mobileVitals: false,
                                                                  .custom: false,
                                                                  .errors: true,
                                                                  .userActions: false,
                                                                  .network: true,
                                                                  .anr: false,
                                                                  .lifeCycle: false],
                                               collectIPData: true,
                                               beforeSend: { cxRum in
            var editableCxRum = cxRum
            if var sessionContext = editableCxRum["session_context"] as? [String: Any] {
                sessionContext["user_email"] = "jone.dow@coralogix.com"
                editableCxRum["session_context"] = sessionContext
            }
            return editableCxRum
        },
                                                debug: true)
        AppDelegate.coralogixRum = CoralogixRum(options: options)
        
        // Must be initialized after CoralogixRum
        let sessionReplayOptions = SessionReplayOptions(imageRecordingType: true,
                                                        captureTimeInterval: 10.0,
                                                        captureScale: 2.0,
                                                        captureCompressionQuality: 0.8,
                                                        maskText: ["Stop"],
                                                        maskImages: true ,
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

