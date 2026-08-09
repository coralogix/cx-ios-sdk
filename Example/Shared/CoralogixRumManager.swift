//
//  CoralogixRumManager.swift
//  DemoApp
//
//  Created by Tomer Har Yoffi on 25/05/2025.
//

import Coralogix
import CoralogixInternal
import Foundation
import UIKit
//import os

// The demo target has its own `Keys` enum (UI labels), which shadows the SDK's wire-key
// registry — alias the registry so payload keys stay typo-proof against the SDK schema.
private typealias WireKeys = CoralogixInternal.Keys

final class CoralogixRumManager {
    static let shared = CoralogixRumManager()

    /// Demo of the customer-side lever for masked interactions (`is_masked_element`):
    /// the SDK default redacts only `target_element_inner_text`; this callback upgrades
    /// every *other* masked interaction to full masking, so the platform shows the two
    /// strategies side by side. Events it fully masks are marked inside the attributes
    /// map (`demo_masking_strategy`, `demo_masked_fields` — demo-authored custom keys,
    /// not SDK wire keys, hence not in the `Keys` registry).
    static let maskedInteractionBeforeSend: ([String: Any]) -> [String: Any]? = { cxRum in
        guard var interaction = cxRum[WireKeys.interactionContext.rawValue] as? [String: Any],
              interaction[WireKeys.isMaskedElement.rawValue] as? Bool == true else {
            return cxRum
        }

        // Alternate: odd masked events keep the SDK default, even ones get full masking.
        guard nextMaskedEventGetsFullMasking() else { return cxRum }

        let fieldsToMask = [WireKeys.targetElement.rawValue,
                            WireKeys.elementClasses.rawValue,
                            WireKeys.elementId.rawValue,
                            WireKeys.targetElementInnerText.rawValue]
        for field in fieldsToMask where interaction[field] != nil {
            interaction[field] = WireKeys.maskedInnerText.rawValue
        }

        // Coordinates travel inside the attributes map; blank them there and record
        // what this callback masked so the two strategies are tellable apart in RUM.
        var attributes = interaction[WireKeys.attributes.rawValue] as? [String: Any] ?? [:]
        let maskedCoordinates = [WireKeys.positionX.rawValue, WireKeys.positionY.rawValue]
            .filter { attributes[$0] != nil }
        for coordinate in maskedCoordinates {
            attributes[coordinate] = 0
        }
        attributes["demo_masking_strategy"] = "before_send_full"
        attributes["demo_masked_fields"] = (fieldsToMask + maskedCoordinates)
            .joined(separator: ",")
        interaction[WireKeys.attributes.rawValue] = attributes

        var editable = cxRum
        editable[WireKeys.interactionContext.rawValue] = interaction
        return editable
    }

    // beforeSend may run concurrently across exporter instances; the increment and the
    // parity read form one critical section so the odd/even alternation stays exact.
    private static var maskedInteractionCounter = 0
    private static let maskedInteractionCounterLock = NSLock()

    private static func nextMaskedEventGetsFullMasking() -> Bool {
        maskedInteractionCounterLock.lock()
        defer { maskedInteractionCounterLock.unlock() }
        maskedInteractionCounter += 1
        return maskedInteractionCounter % 2 == 0
    }

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
        // Proxy resolution, in priority order: a nonempty CX_MOCK_PORT env override wins,
        // then Envs.PROXY_URL from the gitignored per-environment `Example/envs.swift`.
        // An empty configured URL means no proxy — events go straight to the ingress.
        let proxyUrl: String? = {
            if let port = ProcessInfo.processInfo.environment["CX_MOCK_PORT"], !port.isEmpty {
                return "http://127.0.0.1:\(port)"
            }
            let configured = Envs.PROXY_URL.rawValue
            return configured.isEmpty ? nil : configured
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
                                               proxyUrl: proxyUrl,
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
