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

    private var _sdk: CoralogixRum?
    var sdk: CoralogixRum {
        guard let _sdk = _sdk else {
            fatalError("CoralogixRumManager must be initialized before accessing sdk")
        }
        return _sdk
    }
    private init() {}

    private static let testExportPath = "/tmp/coralogix_validation_response.json"
    private let testExportQueue = DispatchQueue(label: "com.coralogix.uitesting.export")

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
                                               tracesExporter: Self.makeUITestingTracesExporter(queue: self.testExportQueue),
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

    // MARK: - UI testing span capture

    /// Returns a `tracesExporter` callback that mirrors the Coralogix backend's
    /// "logs" shape into a local file when the host app is launched with
    /// `--uitesting`. UI tests poll the file instead of waiting for the real
    /// ingest pipeline + schema-validator round-trip. Returns nil otherwise.
    private static func makeUITestingTracesExporter(queue: DispatchQueue) -> TracesExporterCallback? {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return nil }
        return { data in
            let entries = data.tracesData.resourceSpans
                .flatMap { $0.scopeSpans }
                .flatMap { $0.spans }
                .map(spanToLogEntry)
            queue.async {
                var existing: [[String: Any]] = []
                if let raw = try? Data(contentsOf: URL(fileURLWithPath: testExportPath)),
                   let arr = try? JSONSerialization.jsonObject(with: raw) as? [[String: Any]] {
                    existing = arr
                }
                existing.append(contentsOf: entries)
                if let out = try? JSONSerialization.data(withJSONObject: existing) {
                    try? out.write(to: URL(fileURLWithPath: testExportPath))
                }
            }
        }
    }

    /// Converts an OTLP span into the nested `{ "text": { "cx_rum": { ... } } }`
    /// shape that UI test assertions walk. Flat dotted attribute keys
    /// (`cx_rum.interaction_context.event_name`) become nested paths.
    private static func spanToLogEntry(_ span: OtlpSpan) -> [String: Any] {
        var nested: [String: Any] = [:]
        for kv in span.attributes {
            let path = kv.key.split(separator: ".").map(String.init)
            setNested(&nested, path: path, value: unwrap(kv.value))
        }
        return ["text": nested]
    }

    private static func unwrap(_ v: OtlpAnyValue) -> Any {
        switch v {
        case .stringValue(let s): return s
        case .boolValue(let b): return b
        case .intValue(let i): return i
        case .doubleValue(let d): return d
        case .arrayValue(let arr): return arr.map(unwrap)
        case .kvlistValue(let kvs):
            var out: [String: Any] = [:]
            for kv in kvs { out[kv.key] = unwrap(kv.value) }
            return out
        }
    }

    private static func setNested(_ dict: inout [String: Any], path: [String], value: Any) {
        guard let head = path.first else { return }
        if path.count == 1 {
            dict[head] = value
            return
        }
        var sub = (dict[head] as? [String: Any]) ?? [:]
        var rest = path
        rest.removeFirst()
        setNested(&sub, path: rest, value: value)
        dict[head] = sub
    }
}
