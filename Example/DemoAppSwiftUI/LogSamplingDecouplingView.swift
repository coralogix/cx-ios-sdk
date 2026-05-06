//
//  LogSamplingDecouplingView.swift
//  DemoAppSwiftUI
//
//  SwiftUI counterpart of LogSamplingDecouplingViewController. Pick a sample
//  rate + exclude set, reinitialize the SDK, fire events, and watch which
//  event_types survive the sampling filter via the tracesExporter callback.
//

import SwiftUI
import Coralogix
import CoralogixInternal

private struct CapturedSpan: Identifiable {
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

private enum LogSamplingState {
    static var sampleRate: Int = 0
    static var exclude: Set<ExcludableInstrumentation> = [.logs]
    static var isApplied = false
    static var captured: [CapturedSpan] = []
}

struct LogSamplingDecouplingView: View {

    private static let allExcludable: [ExcludableInstrumentation] =
        [.logs, .errors, .network, .userInteractions, .mobileVitals, .customSpan, .customMeasurement]

    @State private var sampleRate: Int = LogSamplingState.sampleRate
    @State private var exclude: Set<ExcludableInstrumentation> = LogSamplingState.exclude
    @State private var isApplied: Bool = LogSamplingState.isApplied
    @State private var captured: [CapturedSpan] = LogSamplingState.captured
    @State private var toastMessage: String?

    var body: some View {
        Form {
            Section("sessionSampleRate") {
                Picker("Sample rate", selection: $sampleRate) {
                    Text("0%").tag(0)
                    Text("50%").tag(50)
                    Text("100%").tag(100)
                }
                .pickerStyle(.segmented)
                .onChange(of: sampleRate) { LogSamplingState.sampleRate = $0 }
            }

            Section("excludeFromSampling") {
                ForEach(Self.allExcludable, id: \.self) { excludable in
                    Toggle(".\(excludable.rawValue)",
                           isOn: bindingForExclude(excludable))
                }
            }

            Section {
                statusText
                Button {
                    apply()
                } label: {
                    Label("Apply (reinit SDK)", systemImage: "arrow.clockwise.circle")
                }
            }

            Section("Applied config") {
                if isApplied {
                    Text(appliedConfigText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("(not applied — tap Apply to reinit the SDK)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("Trigger events") {
                Button { triggerLog() } label: { Label("Send Log", systemImage: "text.bubble") }
                Button { triggerError() } label: { Label("Send Error", systemImage: "exclamationmark.triangle") }
                Button { triggerNetwork() } label: { Label("Send Network", systemImage: "network") }
                Button { triggerCustomSpan() } label: { Label("Send Custom Span", systemImage: "point.3.connected.trianglepath.dotted") }
            }
            .disabled(!isApplied)

            Section {
                HStack {
                    Text("Captured (tracesExporter)")
                        .font(.headline)
                    Spacer()
                    Button {
                        LogSamplingState.captured.removeAll()
                        captured = []
                    } label: {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .disabled(captured.isEmpty)
                }

                if captured.isEmpty {
                    Text("(no spans yet — apply a config and trigger events)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(captured) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.eventType)
                                .font(.system(.callout, design: .monospaced))
                            Text("\(row.timeString)  ·  \(row.name)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Log Sampling Decoupling")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Log Sampling Decoupling")
        .toast(message: $toastMessage)
    }

    // MARK: - Computed views / state

    private var statusText: some View {
        Group {
            if sampleRate == 0 && exclude.isEmpty {
                Text("⚠️ rate=0 + exclude=[] would short-circuit init (legacy contract). Apply will refuse this combination.")
                    .foregroundColor(.orange)
            } else if sampleRate == 100 {
                Text("ℹ️ Sampled in: every event passes regardless of excludeFromSampling.")
                    .foregroundColor(.secondary)
            } else if sampleRate == 0 {
                Text("ℹ️ Sampled out (rate=0): only event_types in excludeFromSampling will be exported.")
                    .foregroundColor(.secondary)
            } else {
                Text("ℹ️ ~\(sampleRate)% of fresh sessions roll sampled-in. Reinit (or relaunch) to roll a new session.")
                    .foregroundColor(.secondary)
            }
        }
        .font(.footnote)
    }

    private var appliedConfigText: String {
        "rate=\(LogSamplingState.sampleRate)\n" +
        "exclude=\(formatExclude(LogSamplingState.exclude))\n" +
        "isInitialized=\(CoralogixRumManager.shared.sdk.isInitialized)"
    }

    private func bindingForExclude(_ excludable: ExcludableInstrumentation) -> Binding<Bool> {
        Binding(
            get: { exclude.contains(excludable) },
            set: { isOn in
                if isOn { exclude.insert(excludable) } else { exclude.remove(excludable) }
                LogSamplingState.exclude = exclude
            }
        )
    }

    // MARK: - Actions

    private func apply() {
        if sampleRate == 0 && exclude.isEmpty {
            toastMessage = "sampleRate=0 + exclude=[] would skip init. Pick a rate or an exclude."
            return
        }

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
            tracesExporter: { data in
                let now = Date()
                var rows: [CapturedSpan] = []
                for resourceSpan in data.tracesData.resourceSpans {
                    for scopeSpan in resourceSpan.scopeSpans {
                        for span in scopeSpan.spans {
                            rows.append(CapturedSpan(
                                eventType: eventType(in: span) ?? "(no event_type)",
                                name: span.name,
                                receivedAt: now
                            ))
                        }
                    }
                }
                guard !rows.isEmpty else { return }
                DispatchQueue.main.async {
                    LogSamplingState.captured.insert(contentsOf: rows.reversed(), at: 0)
                    captured = LogSamplingState.captured
                }
            },
            debug: true
        )
        CoralogixRumManager.shared.reinitialize(with: options)
        LogSamplingState.sampleRate = sampleRate
        LogSamplingState.exclude = exclude
        LogSamplingState.isApplied = true
        isApplied = true
        toastMessage = "SDK reinitialized — rate=\(sampleRate), exclude=\(formatExclude(exclude))"
    }

    private func triggerLog() {
        CoralogixRumManager.shared.sdk.log(severity: .info,
                                           message: "Sampling demo log",
                                           data: ["source": "LogSamplingDecouplingView"])
        toastMessage = "log() called"
    }

    private func triggerError() {
        CoralogixRumManager.shared.sdk.reportError(message: "Sampling demo error", data: nil)
        toastMessage = "reportError() called"
    }

    private func triggerNetwork() {
        NetworkSim.sendSuccesfullRequest()
        toastMessage = "Network request sent"
    }

    private func triggerCustomSpan() {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { toastMessage = "SDK not initialized"; return }
        guard let tracer = rum.getCustomTracer() else { toastMessage = "Failed to get custom tracer"; return }
        guard let global = tracer.startGlobalSpan(name: "sampling-demo.global",
                                                   labels: ["source": "LogSamplingDecouplingView"]) else {
            toastMessage = "startGlobalSpan returned nil"
            return
        }
        let child = global.startCustomSpan(name: "sampling-demo.child")
        child.endSpan()
        global.endSpan()
        toastMessage = "Custom span emitted"
    }

    // MARK: - Helpers

    private func formatExclude(_ set: Set<ExcludableInstrumentation>) -> String {
        if set.isEmpty { return "[]" }
        return "[" + set.map { ".\($0.rawValue)" }.sorted().joined(separator: ", ") + "]"
    }
}

private func eventType(in span: OtlpSpan) -> String? {
    guard let kv = span.attributes.first(where: { $0.key == CoralogixInternal.Keys.eventType.rawValue }) else { return nil }
    if case .stringValue(let value) = kv.value { return value }
    return nil
}
