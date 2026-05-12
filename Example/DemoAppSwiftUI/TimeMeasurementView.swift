//
//  TimeMeasurementView.swift
//  DemoAppSwiftUI
//
//  SwiftUI presenter on top of TimeMeasurementDemoModel — exercise startTimeMeasure /
//  endTimeMeasure manually (name + labels TextFields, Start / End buttons) or via
//  the Quick presets, then watch the resulting custom-measurement spans land in the
//  Captured list via the model's tracesExporter callback.
//

import SwiftUI
import Coralogix
import CoralogixInternal

struct TimeMeasurementView: View {

    @ObservedObject private var model = TimeMeasurementDemoModel.shared
    @State private var toastMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    toastMessage = model.apply()
                } label: {
                    Label("Apply (reinit SDK)", systemImage: "arrow.clockwise.circle")
                }
                Text("Apply rebuilds the SDK on EU2 with sampleRate=100 and a tracesExporter that captures custom-measurement spans below.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section("Status") {
                if model.isApplied {
                    Text(model.appliedConfigDescription)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("(not applied — tap Apply to reinit the SDK with the tracesExporter)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("Manual") {
                HStack {
                    Text("name").frame(width: 60, alignment: .leading)
                    TextField("checkout", text: $model.timerName)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
                HStack {
                    Text("labels").frame(width: 60, alignment: .leading)
                    TextField("key=value, key2=value2", text: $model.labelsText)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
                HStack(spacing: 8) {
                    Button { toastMessage = model.start() } label: {
                        Label("Start", systemImage: "play.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { toastMessage = model.end() } label: {
                        Label("End", systemImage: "stop.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                if model.inFlight.isEmpty {
                    Text("No in-flight timers.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text("In-flight: \(model.inFlight.sorted().joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!model.isApplied)

            Section("Quick presets") {
                Button { toastMessage = model.runQuick(label: "100ms", sleepMs: 100) } label: {
                    Label("Run 100ms", systemImage: "timer")
                }
                Button { toastMessage = model.runQuick(label: "500ms", sleepMs: 500) } label: {
                    Label("Run 500ms", systemImage: "timer")
                }
                Button { toastMessage = model.runQuick(label: "1s", sleepMs: 1000) } label: {
                    Label("Run 1s", systemImage: "timer")
                }
                Text("Each preset starts a measurement, sleeps on a background queue, then ends. Labels: preset=<size>, sleepMs=<n>.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                    Text("(no spans yet — apply, then trigger a measurement)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.captured) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.name)  ·  \(row.durationString)")
                                .font(.system(.callout, design: .monospaced))
                            HStack {
                                Text(row.timeString)
                                if !row.labelsString.isEmpty {
                                    Text("· \(row.labelsString)")
                                }
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Custom Time Measurement")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Custom Time Measurement")
        .toast(message: $toastMessage)
    }
}
