//
//  LogSamplingDecouplingView.swift
//  DemoAppSwiftUI
//
//  SwiftUI presenter on top of LogSamplingDemoModel — pick a sessionSampleRate +
//  excludeFromSampling set, reinitialize the SDK, fire events, and watch which
//  event_types survive the sampling filter via the tracesExporter callback.
//

import SwiftUI
import Coralogix
import CoralogixInternal

struct LogSamplingDecouplingView: View {

    @ObservedObject private var model = LogSamplingDemoModel.shared
    @State private var toastMessage: String?

    var body: some View {
        Form {
            Section("sessionSampleRate") {
                Picker("Sample rate", selection: $model.sampleRate) {
                    Text("0%").tag(0)
                    Text("50%").tag(50)
                    Text("100%").tag(100)
                }
                .pickerStyle(.segmented)
            }

            Section("excludeFromSampling") {
                ForEach(LogSamplingDemoModel.allExcludable, id: \.self) { excludable in
                    Toggle(".\(excludable.rawValue)", isOn: bindingForExclude(excludable))
                }
            }

            Section {
                statusText
                Button {
                    toastMessage = model.apply()
                } label: {
                    Label("Apply (reinit SDK)", systemImage: "arrow.clockwise.circle")
                }
                Text("Apply rebuilds the SDK on EU2 with all instrumentations on; overrides the initial CoralogixRumManager config.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section("Applied config") {
                if model.isApplied {
                    Text("rate=\(model.appliedSampleRate)\nexclude=\(model.formattedAppliedExclude)\nisInitialized=\(CoralogixRumManager.shared.sdk.isInitialized)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("(not applied — tap Apply to reinit the SDK)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("Trigger events") {
                Button { toastMessage = model.triggerLog() } label: { Label("Send Log", systemImage: "text.bubble") }
                Button { toastMessage = model.triggerError() } label: { Label("Send Error", systemImage: "exclamationmark.triangle") }
                Button { toastMessage = model.triggerNetwork() } label: { Label("Send Network", systemImage: "network") }
                Button { toastMessage = model.triggerCustomSpan() } label: { Label("Send Custom Span", systemImage: "point.3.connected.trianglepath.dotted") }
                Button { toastMessage = model.triggerCustomMeasurement() } label: { Label("Send Custom Measurement", systemImage: "ruler") }
            }
            .disabled(!model.isApplied)

            Section {
                HStack {
                    Text("Captured (tracesExporter)")
                        .font(.headline)
                    Spacer()
                    Button {
                        model.clearCaptured()
                    } label: {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .disabled(model.captured.isEmpty)
                }

                if model.captured.isEmpty {
                    Text("(no spans yet — apply a config and trigger events)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.captured) { row in
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

    @SwiftUI.ViewBuilder
    private var statusText: some View {
        Group {
            if model.sampleRate == 0 && model.exclude.isEmpty {
                Text("⚠️ rate=0 + exclude=[] would short-circuit init (legacy contract). Apply will refuse this combination.")
                    .foregroundColor(.orange)
            } else if model.sampleRate == 100 {
                Text("ℹ️ Sampled in: every event passes regardless of excludeFromSampling.")
                    .foregroundColor(.secondary)
            } else if model.sampleRate == 0 {
                Text("ℹ️ Sampled out (rate=0): only event_types in excludeFromSampling will be exported.")
                    .foregroundColor(.secondary)
            } else {
                Text("ℹ️ ~\(model.sampleRate)% of fresh sessions roll sampled-in. Reinit (or relaunch) to roll a new session.")
                    .foregroundColor(.secondary)
            }
        }
        .font(.footnote)
    }

    private func bindingForExclude(_ excludable: ExcludableInstrumentation) -> Binding<Bool> {
        Binding(
            get: { model.exclude.contains(excludable) },
            set: { isOn in
                if isOn { model.exclude.insert(excludable) } else { model.exclude.remove(excludable) }
            }
        )
    }
}
