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
    init() {
        CoralogixRumManager.shared.initialize()
        let sessionReplayOptions = SessionReplayOptions(recordingType: .image,
                                                        captureScale: 2.0,
                                                        captureCompressionQuality: 0.8,
                                                        maskText: nil,
                                                        maskOnlyCreditCards: false,
                                                        maskAllImages: true,
                                                        autoStartSessionRecording: true)
        SessionReplay.initializeWithOptions(sessionReplayOptions: sessionReplayOptions)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
