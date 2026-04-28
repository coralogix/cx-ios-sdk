import SwiftUI
import Coralogix

private struct SpanRow: Identifiable {
    let id = UUID()
    let name: String
    let spanId: String
    let traceId: String
    let parentSpanId: String?
    let kindShort: String
    let receivedAt: Date
    let prettyJson: String
    var isExpanded = false

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: receivedAt)
    }

    var isChild: Bool { parentSpanId != nil }
}

struct TracesExporterView: View {
    @State private var isEnabled = TracesExporterState.isEnabled
    @State private var spans: [SpanRow] = TracesExporterState.spans
    @State private var toastMessage: String?
    @State private var showReinitAlert = false

    var body: some View {
        VStack(spacing: 0) {
            controlsPanel
            Divider()
            spanList
        }
        .navigationTitle("Traces Exporter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !spans.isEmpty {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { copyAll() } label: { Image(systemName: "doc.on.doc") }
                    Button { clearSpans() } label: { Image(systemName: "trash").foregroundColor(.red) }
                }
            }
        }
        .trackCXView(name: "Traces Exporter")
        .alert("Reinitialize SDK", isPresented: $showReinitAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reinitialize") { performReinitialize() }
        } message: {
            Text("Shuts down the current SDK and reinitializes it with the tracesExporter callback enabled.")
        }
        .toast(message: $toastMessage)
    }

    private var controlsPanel: some View {
        VStack(spacing: 6) {
            Text(isEnabled
                 ? "✅ Traces Exporter enabled — \(spans.count) span(s) received"
                 : "⚠️ Reinitialize SDK to enable the Traces Exporter"
            )
            .font(.footnote)
            .foregroundColor(isEnabled ? .secondary : .orange)
            .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                controlButton(icon: "arrow.clockwise.circle", title: "Reinitialize SDK\nwith Traces Exporter",
                              enabled: !isEnabled) {
                    showReinitAlert = true
                }
                controlButton(icon: "network", title: "Trigger Network\nRequest",
                              enabled: isEnabled) {
                    NetworkSim.sendSuccesfullRequest()
                    toastMessage = "Network request sent"
                }
                controlButton(icon: "point.3.connected.trianglepath.dotted", title: "Trigger Custom\nSpan",
                              enabled: isEnabled) {
                    triggerCustomSpan()
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private func controlButton(icon: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    @ViewBuilder
    private var spanList: some View {
        if spans.isEmpty {
            VStack {
                Spacer()
                Text("No spans received yet.\nReinitialize the SDK and trigger a request.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
        } else {
            List {
                ForEach($spans) { $span in
                    spanRow(span: $span)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 8))
                }
            }
            .listStyle(.plain)
        }
    }

    private func spanRow(span: Binding<SpanRow>) -> some View {
        let s = span.wrappedValue
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("  \(s.kindShort)  ")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 2)
                    .background(s.isChild ? Color.green : Color.indigo)
                    .cornerRadius(6)
                    .frame(minWidth: 52)

                Text(s.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer()

                Text(s.timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    UIPasteboard.general.string = s.prettyJson
                    toastMessage = "Copied"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }

                Button {
                    span.isExpanded.toggle()
                    updateState()
                } label: {
                    Image(systemName: s.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }

            Text("spanId: \(s.spanId)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)

            let tracePrefix = s.traceId.count > 16 ? String(s.traceId.prefix(16)) + "…" : s.traceId
            let traceText = s.parentSpanId.map { "traceId: \(tracePrefix)  ↑ \($0)" } ?? "traceId: \(tracePrefix)"
            Text(traceText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(.tertiaryLabel))

            if s.isExpanded {
                Divider()
                Text(s.prettyJson)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func performReinitialize() {
        CoralogixRumManager.shared.sdk.shutdown()
        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: UserContext(userId: "traces-exporter-test", userName: "Test User",
                                     userEmail: "test@example.com", userMetadata: ["test": "tracesExporter"]),
            environment: "PROD",
            application: "DemoApp-iOS-TracesExporter",
            version: "1",
            publicKey: Envs.PUBLIC_KEY.rawValue,
            instrumentations: [.mobileVitals: true, .custom: true, .errors: true,
                                .userActions: true, .network: true, .anr: true, .lifeCycle: true],
            collectIPData: true,
            traceParentInHeader: ["enable": true],
            tracesExporter: { data in
                let now = Date()
                var newRows: [SpanRow] = []
                for resourceSpan in data.tracesData.resourceSpans {
                    for scopeSpan in resourceSpan.scopeSpans {
                        for span in scopeSpan.spans {
                            let kind: String
                            switch span.kind {
                            case .client:     kind = "CLIENT"
                            case .server:     kind = "SERVER"
                            case .internal:   kind = "INTERNAL"
                            case .producer:   kind = "PRODUCER"
                            case .consumer:   kind = "CONSUMER"
                            case .unspecified: kind = "SPAN"
                            }
                            let json: String
                            if let d = try? JSONEncoder().encode(span),
                               let obj = try? JSONSerialization.jsonObject(with: d),
                               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                               let str = String(data: pretty, encoding: .utf8) {
                                json = str
                            } else {
                                json = span.spanId
                            }
                            newRows.append(SpanRow(name: span.name, spanId: span.spanId,
                                                   traceId: span.traceId, parentSpanId: span.parentSpanId,
                                                   kindShort: kind, receivedAt: now, prettyJson: json))
                        }
                    }
                }
                guard !newRows.isEmpty else { return }
                DispatchQueue.main.async {
                    TracesExporterState.spans.insert(contentsOf: newRows.reversed(), at: 0)
                    self.spans = TracesExporterState.spans
                }
            },
            debug: true
        )
        CoralogixRumManager.shared.reinitialize(with: options)
        TracesExporterState.isEnabled = true
        isEnabled = true
        toastMessage = "SDK reinitialized with Traces Exporter"
    }

    private func triggerCustomSpan() {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { toastMessage = "SDK not initialized"; return }
        guard let tracer = rum.getCustomTracer() else { toastMessage = "Failed to get custom tracer"; return }
        guard let global = tracer.startGlobalSpan(name: "traces-exporter-test.global",
                                                   labels: ["test.source": "TracesExporterView"]) else {
            toastMessage = "startGlobalSpan returned nil"
            return
        }
        let child = global.startCustomSpan(name: "traces-exporter-test.child")
        child.setAttribute(key: "test.step", value: "demo")
        child.endSpan()
        global.endSpan()
        toastMessage = "Custom span triggered"
    }

    private func copyAll() {
        let all = spans.map(\.prettyJson).joined(separator: "\n\n---\n\n")
        UIPasteboard.general.string = all
        toastMessage = "All spans copied"
    }

    private func clearSpans() {
        TracesExporterState.spans = []
        spans = []
    }

    private func updateState() {
        TracesExporterState.spans = spans
    }
}

private enum TracesExporterState {
    static var isEnabled = false
    static var spans: [SpanRow] = []
}
