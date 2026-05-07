//
//  LogSamplingDemoModel.swift
//  DemoApp
//
//  Shared view-model behind both LogSamplingDecoupling screens (UIKit + SwiftUI).
//  Owns the user-selected sampling config, the captured tracesExporter spans, and
//  the SDK reinit flow. SwiftUI consumes this via @ObservedObject; UIKit subscribes
//  to objectWillChange via Combine to drive tableView reloads.
//

import Foundation
import Combine
import Coralogix
import CoralogixInternal

struct CapturedSpan: Identifiable {
    let id = UUID()
    let eventType: String
    let name: String
    let receivedAt: Date

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: receivedAt)
    }
}

final class LogSamplingDemoModel: ObservableObject {
    static let shared = LogSamplingDemoModel()

    @Published var sampleRate: Int = 0
    @Published var exclude: Set<ExcludableInstrumentation> = [.logs]
    @Published var isApplied: Bool = false
    @Published var captured: [CapturedSpan] = []

    /// Bumped on every Apply. Each tracesExporter closure captures its token so late
    /// callbacks from a previous run (still possibly in flight on the BatchSpanProcessor's
    /// queue between shutdown and reinit) can be discarded by the closure's token guard
    /// rather than re-filling the just-cleared list.
    private var runToken: Int = 0

    private init() {}

    static let allExcludable: [ExcludableInstrumentation] =
        [.logs, .errors, .network, .userInteractions, .mobileVitals, .customSpan, .customMeasurement]

    var formattedExclude: String {
        if exclude.isEmpty { return "[]" }
        return "[" + exclude.map { ".\($0.rawValue)" }.sorted().joined(separator: ", ") + "]"
    }

    /// Reinitializes the SDK with the current sampleRate + exclude.
    /// Returns a user-facing status message suitable for a toast.
    @discardableResult
    func apply() -> String {
        if sampleRate == 0 && exclude.isEmpty {
            return "sampleRate=0 + exclude=[] would skip init. Pick a rate or an exclude."
        }

        runToken += 1
        let runToken = self.runToken
        captured.removeAll()

        CoralogixRumManager.shared.sdk.shutdown()
        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: UserContext(userId: "sampling-test",
                                     userName: "Sampling Tester",
                                     userEmail: "sampling@example.com",
                                     userMetadata: ["test": "logSamplingDecoupling"]),
            environment: "PROD",
            application: "DemoApp-iOS-LogSamplingDecoupling",
            version: "1",
            publicKey: Envs.PUBLIC_KEY.rawValue,
            sessionSampleRate: sampleRate,
            excludeFromSampling: exclude,
            instrumentations: [.mobileVitals: true, .custom: true, .errors: true,
                               .userActions: true, .network: true, .anr: true, .lifeCycle: true],
            collectIPData: true,
            traceParentInHeader: ["enable": true],
            tracesExporter: { [weak self] data in
                let now = Date()
                var rows: [CapturedSpan] = []
                for resourceSpan in data.tracesData.resourceSpans {
                    for scopeSpan in resourceSpan.scopeSpans {
                        for span in scopeSpan.spans {
                            rows.append(CapturedSpan(
                                eventType: span.eventType ?? "(no event_type)",
                                name: span.name,
                                receivedAt: now
                            ))
                        }
                    }
                }
                guard !rows.isEmpty else { return }
                DispatchQueue.main.async {
                    guard let self = self, runToken == self.runToken else { return }
                    self.captured.insert(contentsOf: rows.reversed(), at: 0)
                }
            },
            debug: true
        )
        CoralogixRumManager.shared.reinitialize(with: options)

        let didApply = CoralogixRumManager.shared.sdk.isInitialized
        isApplied = didApply
        return didApply
            ? "SDK reinitialized — rate=\(sampleRate), exclude=\(formattedExclude)"
            : "❌ SDK failed to initialize for rate=\(sampleRate), exclude=\(formattedExclude)"
    }

    @discardableResult
    func triggerLog() -> String {
        CoralogixRumManager.shared.sdk.log(severity: .info,
                                            message: "Sampling demo log",
                                            data: ["source": "LogSamplingDemoModel"])
        return "log() called"
    }

    @discardableResult
    func triggerError() -> String {
        CoralogixRumManager.shared.sdk.reportError(message: "Sampling demo error", data: nil)
        return "reportError() called"
    }

    @discardableResult
    func triggerNetwork() -> String {
        NetworkSim.sendSuccesfullRequest()
        return "Network request sent"
    }

    @discardableResult
    func triggerCustomSpan() -> String {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { return "SDK not initialized" }
        guard let tracer = rum.getCustomTracer() else { return "Failed to get custom tracer" }
        guard let global = tracer.startGlobalSpan(name: "sampling-demo.global",
                                                   labels: ["source": "LogSamplingDemoModel"]) else {
            return "startGlobalSpan returned nil"
        }
        let child = global.startCustomSpan(name: "sampling-demo.child")
        child.endSpan()
        global.endSpan()
        return "Custom span emitted"
    }

    @discardableResult
    func triggerCustomMeasurement() -> String {
        CoralogixRumManager.shared.sdk.sendCustomMeasurement(name: "sampling-demo.measurement", value: 42.0)
        return "sendCustomMeasurement() called"
    }

    func clearCaptured() {
        captured.removeAll()
    }
}
