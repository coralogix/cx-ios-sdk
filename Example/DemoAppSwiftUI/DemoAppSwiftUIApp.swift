//
//  DemoAppSwiftUIApp.swift
//  DemoAppSwiftUI
//
//  Created by Coralogix DEV TEAM on 22/05/2024.
//
import SwiftUI
import Coralogix

@main

struct DemoAppSwiftUIApp: App {
    init() {
        CoralogixRumManager.shared.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
