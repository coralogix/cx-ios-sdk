//
//  CoralogixRumManager.swift
//  DemoApp
//
//  Created by Tomer Har Yoffi on 25/05/2025.
//

import Coralogix
import Foundation
import Network
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
                                               tracesExporter: TestSpanCapture.shared.makeTracesExporter(),
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

// MARK: - In-process span capture for UI tests

/// Captures every OTLP batch the SDK exports and serves them over a tiny HTTP
/// endpoint on `127.0.0.1:9999`. Active only when the host app is launched
/// with `--uitesting`.
///
/// Why HTTP, not a file: on the iOS Simulator the host app and the UI test
/// runner are separate processes with sandboxed `/tmp/`; they cannot see each
/// other's files. Both processes share the simulator's loopback interface,
/// so localhost TCP works.
///
/// Endpoints:
///   GET    /spans  → JSON: { "batches": ["<otlp-json>", ...] }
///   DELETE /spans  → clears the in-memory store; returns `{}`
final class TestSpanCapture {
    static let shared = TestSpanCapture()
    static let port: UInt16 = 9999

    private let lock = NSLock()
    private var batches: [String] = []
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.coralogix.uitesting.capture", qos: .utility)

    private init() {}

    /// Returns a `tracesExporter` callback when running under `--uitesting`,
    /// otherwise `nil` so production behaviour is unchanged.
    func makeTracesExporter() -> TracesExporterCallback? {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return nil }
        startListenerIfNeeded()
        return { [weak self] data in
            guard let self, let json = data.jsonString else { return }
            self.lock.lock()
            self.batches.append(json)
            self.lock.unlock()
        }
    }

    private func startListenerIfNeeded() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            do {
                let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
                l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
                l.start(queue: self.queue)
                self.listener = l
                print("🟪 TestSpanCapture: listening on 127.0.0.1:\(Self.port)")
            } catch {
                print("🟪 TestSpanCapture: failed to start listener: \(error)")
            }
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.components(separatedBy: " ")
            let method = parts.first ?? ""
            let path = parts.count > 1 ? parts[1] : ""

            let body: Data
            switch (method, path) {
            case ("GET", "/spans"):
                self.lock.lock()
                let snapshot = self.batches
                self.lock.unlock()
                body = (try? JSONSerialization.data(withJSONObject: ["batches": snapshot])) ?? Data("{}".utf8)
            case ("DELETE", "/spans"):
                self.lock.lock()
                self.batches.removeAll()
                self.lock.unlock()
                body = Data("{}".utf8)
            default:
                body = Data("{}".utf8)
            }

            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            let response = Data(header.utf8) + body
            conn.send(content: response, completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }
}
