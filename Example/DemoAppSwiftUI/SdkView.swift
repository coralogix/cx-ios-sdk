import SwiftUI
import Coralogix

struct SdkView: View {
    @State private var toastMessage: String?
    @State private var showSamplerSheet = false
    @State private var samplerRateText = "50"
    @State private var samplerResult: String?

    var body: some View {
        List {
            Button {
                toastMessage = "Selected: SDK Shutdown"
                CoralogixRumManager.shared.sdk.shutdown()
            } label: {
                demoRow(icon: "power", title: "SDK Shutdown", subtitle: "Stop the Coralogix SDK")
            }

            Button {
                toastMessage = "Selected: Update Labels"
                CoralogixRumManager.shared.sdk.set(labels: ["item3": "playstation 4", "itemPrice": 400])
            } label: {
                demoRow(icon: "tag", title: "Update Labels", subtitle: "Set custom session labels")
            }

            Button {
                toastMessage = "Selected: Report Mobile Vitals"
                CoralogixRumManager.shared.sdk.reportMobileVitalsMeasurement(
                    type: "custom metric", value: 10.0, units: "ms"
                )
            } label: {
                demoRow(icon: "chart.xyaxis.line", title: "Report Mobile Vitals", subtitle: "Custom performance measurement")
            }

            Button {
                toastMessage = "Selected: Custom Labels Log"
                CoralogixRumManager.shared.sdk.log(
                    severity: .info,
                    message: "Custom labels",
                    labels: ["im custom label": "label value", "thats wrong": 0]
                )
            } label: {
                demoRow(icon: "tag.circle", title: "Custom Labels Log", subtitle: "Log message with custom labels")
            }

            Button {
                toastMessage = "Selected: Custom Measurement"
                CoralogixRumManager.shared.sdk.sendCustomMeasurement(name: "LSD", value: 43.0)
            } label: {
                demoRow(icon: "gauge.with.dots.needle.67percent", title: "Custom Measurement", subtitle: "Send custom metric data")
            }

            Button {
                showSamplerSheet = true
            } label: {
                demoRow(icon: "percent", title: "Test Session Sampler", subtitle: "Run sampler trials with a chosen rate (0–100%)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("SDK Functions")
        .navigationBarTitleDisplayMode(.large)
        .trackCXView(name: "SDK Functions")
        .toast(message: $toastMessage)
        .alert("Test Session Sampler", isPresented: $showSamplerSheet, actions: {
            TextField("Sample rate (0–100)", text: $samplerRateText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Run 1000 trials") {
                runSamplerTest()
            }
        }, message: {
            Text("Enter sample rate (0–100). We'll run 1000 trials and show how many would initialize.")
        })
        .alert("Sampler result", isPresented: Binding(
            get: { samplerResult != nil },
            set: { if !$0 { samplerResult = nil } }
        ), actions: {
            Button("OK", role: .cancel) { samplerResult = nil }
        }, message: {
            Text(samplerResult ?? "")
        })
    }

    private func demoRow(icon: String, title: String, subtitle: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 28)
        }
        .padding(.vertical, 2)
    }

    private func runSamplerTest() {
        let rate = max(0, min(100, Int(samplerRateText) ?? 50))
        let sampler = SDKSampler(sampleRate: rate)
        var initialized = 0
        for _ in 0..<1000 {
            if sampler.shouldInitialized() { initialized += 1 }
        }
        let dropped = 1000 - initialized
        samplerResult = "At \(rate)%: \(initialized) would initialize, \(dropped) would not (\(String(format: "%.1f", Double(initialized) / 10))% sampled)."
    }
}
