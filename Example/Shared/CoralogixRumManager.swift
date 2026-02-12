//
//  CoralogixRumManager.swift
//  DemoApp
//
//  Created by Tomer Har Yoffi on 25/05/2025.
//

import Coralogix
import Foundation
//import os

final class CoralogixRumManager {
    static let shared = CoralogixRumManager()

    private var _sdk: CoralogixRum?
    var sdk: CoralogixRum {
        guard let _sdk = _sdk else {
            fatalError("CoralogixRumManager must be initialized before accessing sdk")
        }
        return _sdk
    }
    private init() {}

    func initialize() {
        let userContext = UserContext(userId: "ww",
                                      userName: "?",
                                      userEmail: "a@a.com",
                                      userMetadata: ["d":"d"])
        let options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.EU2,
                                               userContext: userContext,
                                               environment: "PROD",
                                               application: "DemoApp-iOS-swift",
                                               version: "1",
                                               publicKey: Envs.PUBLIC_KEY.rawValue,
                                               instrumentations: [
                                                .mobileVitals: true,
                                                                  .custom: true,
                                                                  .errors: true,
                                                                  .userActions: true,
                                                                  .network: true,
                                                                  .anr: true,
                                                                  .lifeCycle: true],
                                               collectIPData: true,
//                                               beforeSend: { cxRum in
//            var editableCxRum = cxRum
//            if var sessionContext = editableCxRum["session_context"] as? [String: Any] {
//                sessionContext["user_email"] = "jone.dow@coralogix.com"
//                editableCxRum["session_context"] = sessionContext
//            }
//            return editableCxRum
//        },
                                               enableSwizzling: true,
                                               proxyUrl: Envs.PROXY_URL.rawValue, // remove if not need to use proxy
                                               mobileVitals:[.cpuDetector: false,
                                                             .warmDetector: false,
                                                             .coldDetector: false,
                                                             .slowFrozenFramesDetector: false,
                                                             .memoryDetector: false,
                                                             .renderingDetector: false],
                                               debug: true
        )
//        let log = OSLog(subsystem: "test.CoralogixTest", category: .pointsOfInterest)
//        let signpostID = OSSignpostID(log: log)
//        os_signpost(.begin, log: log, name: "Init Coralogix", signpostID: signpostID)
        self._sdk = CoralogixRum(options: options)
//        os_signpost(.end, log: log, name: "Init Coralogix", signpostID: signpostID)
        print("SDK initialized:\(self._sdk?.isInitialized.description ?? "not initialized")")
    }

    func getSessionId() -> String? {
        return _sdk?.getSessionId
    }
}
