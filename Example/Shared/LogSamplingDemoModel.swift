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

    /// Editable selection bound to the UI controls. Reads here drift as the user toggles
    /// the picker/switches and do NOT reflect what the SDK is currently configured with.
    @Published var sampleRate: Int = 0
    @Published var exclude: Set<ExcludableInstrumentation> = [.logs]

    /// Snapshot of the values that were in effect on the last successful Apply. Use these
    /// (not the editable fields above) when displaying "what the SDK is configured with".
    @Published var appliedSampleRate: Int = 0
    @Published var appliedExclude: Set<ExcludableInstrumentation> = []

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

    var formattedAppliedExclude: String { Self.formatExclude(appliedExclude) }

    private static func formatExclude(_ set: Set<ExcludableInstrumentation>) -> String {
        if set.isEmpty { return "[]" }
        return "[" + set.map { ".\($0.rawValue)" }.sorted().joined(separator: ", ") + "]"
    }

    /// Reinitializes the SDK with the current sampleRate + exclude.
    /// Returns a user-facing status message suitable for a toast.
    @discardableResult
    func apply() -> String {
        if sampleRate == 0 && exclude.isEmpty {
            return "sampleRate=0 + exclude=[] would skip init. Pick a rate or an exclude."
        }

        // Snapshot the values being attempted so toast strings and the success-side
        // state-write all use the same numbers, even if the user mutates the editable
        // fields later (the closure below is captured by reference into the SDK).
        let attemptedSampleRate = sampleRate
        let attemptedExclude = exclude
        let attemptedFormatted = Self.formatExclude(attemptedExclude)

        runToken += 1
        let runToken = self.runToken

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
            sessionSampleRate: attemptedSampleRate,
            excludeFromSampling: attemptedExclude,
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
        if didApply {
            // Promote the attempted config into the "applied" snapshot only after the SDK
            // confirms it initialized; clearing captured here (vs. before shutdown) keeps
            // the previous run's rows visible if Apply fails.
            appliedSampleRate = attemptedSampleRate
            appliedExclude = attemptedExclude
            captured.removeAll()
        }
        return didApply
            ? "SDK reinitialized — rate=\(attemptedSampleRate), exclude=\(attemptedFormatted)"
            : "❌ SDK failed to initialize for rate=\(attemptedSampleRate), exclude=\(attemptedFormatted)"
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
        // Bumping runToken first invalidates any tracesExporter callbacks already in
        // flight on BatchSpanProcessor's queue; their main-queue insert will hit the
        // token guard and drop the row instead of repopulating the just-cleared list.
        // Side effect: this also stops the current SDK's *future* spans from being
        // captured (the closure's captured token is now stale). To resume capture,
        // tap Apply again.
        runToken += 1
        captured.removeAll()
    }
}
