//
//  DemoAppApp.swift
//  DemoApp
//
//  Created by Coralogix DEV TEAM on 05/05/2024.
//

import SwiftUI
import CoralogixRum

@main
struct DemoAppApp: App {
    @State private var coralogixRum: CoralogixRum

    init() {
//        let options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.EU2,
//                                               userContext: nil,
//                                               publicKey: "84bd3129-0363-4035-82b2-1874ee1de2cf")
        let options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                               userContext: nil,
                                               environment: "PROD",
                                               application: "DemoApp-iOS",
                                               version: "1",
                                               publicKey: "cxtp_3EBvvOiDcFwgutlSBX507UsXvrSQts",
                                               ignoreUrls: [], //[".*\\.il$", "https://www.coralogix.com/academy"],
                                               ignoreErrors: [], //[".*errorcode=.*", "Im cusom Error"],
                                               customDomainUrl: "https://ingress.staging.rum-ingress-coralogix.com",
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
