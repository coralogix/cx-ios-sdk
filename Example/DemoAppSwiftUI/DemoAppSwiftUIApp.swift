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
        let options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                               userContext: nil,
                                               environment: "PROD",
                                               application: "Application",
                                               version: "1",
                                               publicKey:"PublicKey",
                                               ignoreUrls: [],
                                               ignoreErrors: [],
                                               labels: ["item" : "playstation 5", "itemPrice" : 1000],
                                               debug: true)

        self.coralogixRum = CoralogixRum(options: options)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(coralogixRum: $coralogixRum)
        }
    }
}
