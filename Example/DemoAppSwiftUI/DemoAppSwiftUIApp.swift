//
//  DemoAppSwiftUIApp.swift
//  DemoAppSwiftUI
//
//  Created by Coralogix DEV TEAM on 22/05/2024.
//
import SwiftUI
import Coralogix
import SessionReplay

@main

struct DemoAppSwiftUIApp: App {
    @State private var coralogixRum: CoralogixRum
    init() {
        CoralogixRumManager.shared.initialize()
        // Must be initialized after CoralogixRum
        let sessionReplayOptions = SessionReplayOptions(recordingType: .image,
                                                        captureTimeInterval: 10.0,
                                                        captureScale: 2.0,
                                                        captureCompressionQuality: 0.8,
                                                        maskText: [],
                                                        maskCreditCard: false,
                                                        maskAllImages: false,
                                                        autoStartSessionRecording: true)
        SessionReplay.initializeWithOptions(sessionReplayOptions:sessionReplayOptions)
        
        self.coralogixRum = CoralogixRumManager.shared.sdk
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(coralogixRum: $coralogixRum)
        }
    }
}
