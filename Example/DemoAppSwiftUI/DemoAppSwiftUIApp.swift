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
    @State private var coralogixRum: CoralogixRum
    init() {
        CoralogixRumManager.shared.initialize()
        self.coralogixRum = CoralogixRumManager.shared.sdk
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(coralogixRum: $coralogixRum)
        }
    }
}
