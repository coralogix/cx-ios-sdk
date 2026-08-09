//
//  CoralogixRumManager.swift
//  DemoApp
//
//  Created by Tomer Har Yoffi on 25/05/2025.
//

import Coralogix
import Foundation
import UIKit
//import os

final class CoralogixRumManager {
    static let shared = CoralogixRumManager()

    /// Demo of the customer-side lever for masked interactions (`is_masked_element`):
    /// the SDK default redacts only `target_element_inner_text`; this callback upgrades
    /// every *other* masked interaction to full masking, so the platform shows the two
    /// strategies side by side. Events it fully masks are marked inside the attributes
    /// map (`demo_masking_strategy`, `demo_masked_fields`).
    static let maskedInteractionBeforeSend: ([String: Any]) -> [String: Any]? = { cxRum in
        guard var interaction = cxRum["interaction_context"] as? [String: Any],
              interaction["is_masked_element"] as? Bool == true else {
            return cxRum
        }

        // Alternate: odd masked events keep the SDK default, even ones get full masking.
        // Demo-only counter — beforeSend runs on the exporter's serial encode path.
        maskedInteractionCounter += 1
        guard maskedInteractionCounter % 2 == 0 else { return cxRum }

        let fieldsToMask = ["target_element", "element_classes", "element_id",
                            "target_element_inner_text"]
        for field in fieldsToMask where interaction[field] != nil {
            interaction[field] = "***"
        }

        // Coordinates travel inside the attributes map; blank them there and record
        // what this callback masked so the two strategies are tellable apart in RUM.
        var attributes = interaction["attributes"] as? [String: Any] ?? [:]
        let maskedCoordinates = ["x", "y"].filter { attributes[$0] != nil }
        for coordinate in maskedCoordinates {
            attributes[coordinate] = 0
        }
        attributes["demo_masking_strategy"] = "before_send_full"
        attributes["demo_masked_fields"] = (fieldsToMask + maskedCoordinates)
            .joined(separator: ",")
        interaction["attributes"] = attributes

        var editable = cxRum
        editable["interaction_context"] = interaction
        return editable
    }
    private static var maskedInteractionCounter = 0

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
        // BUGV2-6045 leak-harness override: when the XCUITest harness
        // launches the app it sets CX_MOCK_PORT in the env. Point the
        // session-replay proxy at the host mock server on the simulator
        // host loopback. No effect on normal demo launches.
        let proxyUrl: String? = {
            if let port = ProcessInfo.processInfo.environment["CX_MOCK_PORT"], !port.isEmpty {
                return "http://127.0.0.1:\(port)"
            }
            return Envs.PROXY_URL.rawValue
        }()
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
                                               beforeSend: CoralogixRumManager.maskedInteractionBeforeSend,
                                               enableSwizzling: true,
                                               proxyUrl: proxyUrl, // BUGV2-6045: harness override (CX_MOCK_PORT env), else Envs.PROXY_URL
                                               traceParentInHeader: ["enable": true],
                                               mobileVitals:[.cpuDetector: false,
                                                             .warmDetector: false,
                                                             .coldDetector: false,
                                                             .slowFrozenFramesDetector: false,
                                                             .memoryDetector: false,
                                                             .renderingDetector: false],
                                               networkExtraConfig: [
                                                NetworkCaptureRule(url: "https://jsonplaceholder.typicode.com/posts",
                                                                   reqHeaders: ["Content-Type", "Accept", "X-Demo-Header"],
                                                                   resHeaders: ["Content-Type", "X-Request-Id"],
                                                                   collectReqPayload: true,
                                                                   collectResPayload: true)
                                               ],
                                               shouldSendText: { view, text in
            // Return false to suppress text capture for a specific view.
            return view.accessibilityIdentifier != "sensitiveLabel"
        },
                                               resolveTargetName: { view in
            // Map specific views to meaningful business names.
            // The SDK uses these names as `target_element` in RUM instead of the raw UIKit class.
            switch view.accessibilityIdentifier {
            case "loginButton":      return "Login Button"
            case "checkoutButton":   return "Checkout Button"
            case "promoCodeField":   return "Promo Code Input"
            case "profileAvatar":    return "Profile Avatar"
            default:                 return nil  // nil → SDK falls back to UIKit class name
            }
        },
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
    
    func reinitialize(with options: CoralogixExporterOptions) {
        _sdk?.shutdown()
        _sdk = CoralogixRum(options: options)
        print("SDK reinitialized:\(_sdk?.isInitialized.description ?? "not initialized")")
    }
}
