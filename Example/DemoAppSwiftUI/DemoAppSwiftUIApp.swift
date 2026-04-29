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
                                                        captureTimeInterval: 10.0,
                                                        captureScale: 2.0,
                                                        captureCompressionQuality: 0.8,
                                                        maskText: [],
                                                        maskOnlyCreditCards: false,
                                                        maskAllImages: false,
                                                        autoStartSessionRecording: true)
        SessionReplay.initializeWithOptions(sessionReplayOptions: sessionReplayOptions)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
