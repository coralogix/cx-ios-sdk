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

        // `--mask-all-text` mirrors the customer config (maskAllTexts: true,
        // maskAllImages: false) so the Masking Transitions screen can reproduce
        // the bottom-sheet / back-move masking leak. SwiftUI masks through the
        // Vision-OCR pipeline — the same path used for Flutter.
        let maskAllText = ProcessInfo.processInfo.arguments.contains("--mask-all-text")
        let sessionReplayOptions = SessionReplayOptions(recordingType: .image,
                                                        captureScale: maskAllText ? 1.0 : 2.0,
                                                        captureCompressionQuality: maskAllText ? 1.0 : 0.8,
                                                        maskText: maskAllText ? [".*"] : nil,
                                                        maskOnlyCreditCards: false,
                                                        maskAllImages: !maskAllText,
                                                        autoStartSessionRecording: true)
        SessionReplay.initializeWithOptions(sessionReplayOptions: sessionReplayOptions)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
