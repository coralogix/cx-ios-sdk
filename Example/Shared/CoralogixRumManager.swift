//
//  CoralogixRumManager.swift
//  DemoApp
//
//  Created by Tomer Har Yoffi on 25/05/2025.
//

import Coralogix
//import os

final class CoralogixRumManager {
    static let shared = CoralogixRumManager()

    private(set) var sdk: CoralogixRum!

    private init() {}

    func initialize() {
        let userContext = UserContext(userId: "ww",
                                      userName: "?",
                                      userEmail: "a@a.com",
                                      userMetadata: ["d":"d"])
        let options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.STG,
                                               userContext: userContext,
                                               environment: "PROD",
                                               application: "REPLACE_ME", // TODO: replace with real application name
                                               version: "1",
                                               publicKey: "REPLACE_ME", // TODO: replace with real publicKey name
                                               instrumentations: [.mobileVitals: true,
                                                                  .custom: true,
                                                                  .errors: true,
                                                                  .userActions: true,
                                                                  .network: true,
                                                                  .anr: true,
                                                                  .lifeCycle: true],
                                               collectIPData: true,
                                               beforeSend: { cxRum in
            var editableCxRum = cxRum
            if var sessionContext = editableCxRum["session_context"] as? [String: Any] {
                sessionContext["user_email"] = "jone.dow@coralogix.com"
                editableCxRum["session_context"] = sessionContext
            }
            return editableCxRum
        },
                                               enableSwizzling: true,
                                               debug: true)
//        let log = OSLog(subsystem: "test.CoralogixTest", category: .pointsOfInterest)
//        let signpostID = OSSignpostID(log: log)
//        os_signpost(.begin, log: log, name: "Init Coralogix", signpostID: signpostID)
        self.sdk = CoralogixRum(options: options)
//        os_signpost(.end, log: log, name: "Init Coralogix", signpostID: signpostID)
    }
}
