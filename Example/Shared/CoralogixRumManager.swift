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
                                               tracesExporter: MarshalSpanCapture.shared.makeTracesExporter(),
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

// MARK: - UI test marshal-field span capture (Phase 2.2 v3)

/// Captures interaction events for UI tests by serializing them into a hidden
/// `UITextField`'s `accessibilityValue`. UI tests read the field via XCUI:
///
///     app.textFields["coralogix.uitesting.marshal"].value as? String
///
/// Active only when the host app is launched with `--uitesting`. Production
/// behaviour is unchanged.
///
/// Why a marshal text field and not HTTP/file IPC: the iOS Simulator
/// sandboxes `/tmp/` per-process and `NWListener`-based localhost adds
/// non-trivial infrastructure. The accessibility tree crosses process
/// boundaries natively, so the test runner can read this field without any
/// IPC plumbing — pattern borrowed from `sentry-cocoa`'s
/// `UITestHelpers.marshalJSONDictionaryFromApp(...)`.
final class MarshalSpanCapture {
    static let shared = MarshalSpanCapture()
    static let fieldIdentifier = "coralogix.uitesting.marshal"

    private let lock = NSLock()
    private var events: [[String: Any]] = []
    private weak var marshalField: UITextField?

    private init() {}

    /// Returns a `tracesExporter` callback when running under `--uitesting`,
    /// otherwise `nil`.
    ///
    /// Disabled for the SwiftUI demo app: injecting a `UITextField` subview
    /// into `UIHostingController.view` and mutating its `accessibilityValue`
    /// every batch triggered SwiftUI layout invalidation cycles that
    /// saturated the main thread, leaving the app un-terminable at test
    /// teardown (`Failed to terminate com.coralogix.DemoAppSwiftUI` in
    /// run 25440150722). Phase 2 migrations only target UIKit tests, so
    /// the SwiftUI app keeps the existing schema-validator path until we
    /// design a SwiftUI-safe transport.
    func makeTracesExporter() -> TracesExporterCallback? {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return nil }
        if Bundle.main.bundleIdentifier?.contains("SwiftUI") == true { return nil }
        return { [weak self] data in
            self?.handle(data)
        }
    }

    private func handle(_ data: CoralogixTraceExporterData) {
        let newEvents = Self.extractInteractionEvents(from: data)
        print("🟪 [Marshal] handle: spanCount=\(data.spanCount) interactionEvents=\(newEvents.count)")
        guard !newEvents.isEmpty else { return }

        lock.lock()
        events.append(contentsOf: newEvents)
        let snapshot = events
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.publish(snapshot)
        }
    }

    private func publish(_ events: [[String: Any]]) {
        guard let json = try? JSONSerialization.data(withJSONObject: events),
              let str = String(data: json, encoding: .utf8) else {
            print("🟪 [Marshal] publish: JSON serialization failed for events=\(events.count)")
            return
        }

        let field = ensureMarshalField()
        print("🟪 [Marshal] publish: events=\(events.count) bytes=\(str.count) field=\(field != nil ? "installed" : "nil")")
        field?.accessibilityValue = str
    }

    private func ensureMarshalField() -> UITextField? {
        if let field = marshalField, field.window != nil { return field }
        guard let host = Self.hostView() else {
            print("🟪 [Marshal] ensureMarshalField: hostView() returned nil")
            return nil
        }

        // 1×1 at origin (NOT off-screen): iOS's accessibility tree typically
        // prunes views whose frame is fully outside the parent's bounds, which
        // makes XCUI's snapshot exclude them entirely. On-screen + alpha 0.01
        // is what `sentry-cocoa`'s marshal field uses for the same reason.
        // The earlier keyWindow placement broke `testSchemaValidationFlow`'s
        // staticTexts traversal — scoping to the top-most VC's view fixes
        // that without sacrificing reachability.
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        field.accessibilityIdentifier = Self.fieldIdentifier
        field.isAccessibilityElement = true
        field.alpha = 0.01
        field.isUserInteractionEnabled = false
        host.addSubview(field)
        marshalField = field
        print("🟪 [Marshal] ensureMarshalField: installed in \(type(of: host)) hostInWindow=\(host.window != nil)")
        return field
    }

    /// Returns the top-most presented view controller's view. The marshal
    /// field rides along with whatever screen is currently on; if the user
    /// navigates, the previous field deallocates and the next callback
    /// installs a fresh one on the new VC's view (idempotent — still
    /// queryable by the same accessibilityIdentifier).
    private static func hostView() -> UIView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first,
              var current = window.rootViewController else { return nil }
        while let presented = current.presentedViewController {
            current = presented
        }
        return current.view
    }

    /// Walks the OTLP batch JSON and pulls out interaction events. The SDK
    /// packs each interaction's fields into a single `tapObject` attribute
    /// whose value is a JSON-encoded string (per
    /// `Coralogix/Sources/Model/Contexts/InteractionContext.swift`). We
    /// decode that string here so test assertions can match on flat keys
    /// like `event_name`, `scroll_direction`, `target_element`.
    private static func extractInteractionEvents(from data: CoralogixTraceExporterData) -> [[String: Any]] {
        guard let jsonData = data.jsonData,
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let resourceSpans = root["resourceSpans"] as? [[String: Any]] else { return [] }

        var result: [[String: Any]] = []
        for rs in resourceSpans {
            guard let scopeSpans = rs["scopeSpans"] as? [[String: Any]] else { continue }
            for ss in scopeSpans {
                guard let spans = ss["spans"] as? [[String: Any]] else { continue }
                for span in spans {
                    guard let attrs = span["attributes"] as? [[String: Any]] else { continue }
                    guard let tapObjAttr = attrs.first(where: { ($0["key"] as? String) == "tapObject" }),
                          let valueObj = tapObjAttr["value"] as? [String: Any],
                          let jsonString = valueObj["stringValue"] as? String,
                          let stringData = jsonString.data(using: .utf8),
                          let dict = try? JSONSerialization.jsonObject(with: stringData) as? [String: Any]
                    else { continue }
                    result.append(dict)
                }
            }
        }
        return result
    }
}
