import SwiftUI
import Coralogix

struct CustomSpansView: View {
    @State private var toastMessage: String?
    @State private var cachedTracer: CoralogixCustomTracer?
    @State private var cachedTracerPreferIgnored: Bool?

    private struct DemoItem {
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }

    private var items: [DemoItem] {
        [
            DemoItem(
                title: "Simple global + child spans",
                subtitle: "Simulates a small user flow: startGlobalSpan → startCustomSpan (child) → set attribute, event, status → end child → end global. You should see two custom-span events on one trace in Coralogix.",
                icon: "point.3.connected.trianglepath.dotted",
                action: { runSimpleFlow(useIgnoredTracer: false) }
            ),
            DemoItem(
                title: "withContext + GET request",
                subtitle: "Simulates doing work (here a demo GET) while the global span is open. Shows that withContext is safe when the global is already active.",
                icon: "network",
                action: { runWithContextNetwork() }
            ),
            DemoItem(
                title: "Second startGlobalSpan rejected",
                subtitle: "Simulates the Browser rule: with a global still open, a second startGlobalSpan returns nil. After endSpan(), a new global can start.",
                icon: "exclamationmark.triangle",
                action: { runSecondGlobalRejectedDemo() }
            ),
            DemoItem(
                title: "Tracer with ignoredInstruments",
                subtitle: "Same span sequence as the first row, but using getCustomTracer(ignoredInstruments: [.networkRequests, .errors]).",
                icon: "eye.slash",
                action: { runSimpleFlow(useIgnoredTracer: true) }
            )
        ]
    }

    var body: some View {
        List {
            Section {
                Text(introText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("Demos") {
                ForEach(items, id: \.title) { item in
                    Button {
                        item.action()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: item.icon)
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 28)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Custom Spans")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Custom Spans")
        .toast(message: $toastMessage)
    }

    private let introText = """
    Custom spans are manual RUM spans (exported like the Browser SDK, type custom-span). A global span is the "root" for a flow; nested spans are children. Only one global may exist at a time.

    startGlobalSpan registers that span as OpenTelemetry's active context. Auto-instrumentation (e.g. URLSession) can then use the same traceId until you call endSpan().

    Tap a row below to run a scripted sequence; check Coralogix for span names and the shared trace.
    """

    private func tracerForSession(preferIgnored: Bool) -> CoralogixCustomTracer? {
        if let c = cachedTracer {
            if (cachedTracerPreferIgnored ?? false) != preferIgnored {
                toastMessage = "Reusing earlier tracer — ignored-instruments setting differs. Relaunch to switch."
            }
            return c
        }
        let rum = CoralogixRumManager.shared.sdk
        let t: CoralogixCustomTracer?
        if preferIgnored {
            t = rum.getCustomTracer(ignoredInstruments: [.networkRequests, .errors])
        } else {
            t = rum.getCustomTracer()
        }
        guard let tracer = t else {
            toastMessage = "Custom tracer unavailable — set traceParentInHeader with enable: true."
            return nil
        }
        cachedTracer = tracer
        cachedTracerPreferIgnored = preferIgnored
        return tracer
    }

    private func runSimpleFlow(useIgnoredTracer: Bool) {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { toastMessage = "SDK not initialized"; return }
        guard let tracer = tracerForSession(preferIgnored: useIgnoredTracer) else { return }
        guard let global = tracer.startGlobalSpan(name: "demo.custom.global", labels: ["demo.screen": "CustomSpans"]) else {
            toastMessage = "startGlobalSpan returned nil"
            return
        }
        let child = global.startCustomSpan(name: "demo.custom.child")
        child.setAttribute(key: "demo.step", value: "authorize")
        child.addEvent(name: "demo.checkpoint")
        child.setStatus(.ok)
        child.endSpan()
        global.endSpan()
        toastMessage = useIgnoredTracer ? "Finished (ignored-instruments tracer)" : "Finished simple flow"
    }

    private func runSecondGlobalRejectedDemo() {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { toastMessage = "SDK not initialized"; return }
        guard let tracer = tracerForSession(preferIgnored: false) else { return }
        guard let first = tracer.startGlobalSpan(name: "demo.custom.first_global") else {
            toastMessage = "Unexpected: first startGlobalSpan failed"
            return
        }
        if tracer.startGlobalSpan(name: "demo.custom.should_fail") != nil {
            toastMessage = "Bug: second startGlobalSpan should return nil"
            first.endSpan()
            return
        }
        first.endSpan()
        guard let after = tracer.startGlobalSpan(name: "demo.custom.after_end") else {
            toastMessage = "Unexpected: global after endSpan should succeed"
            return
        }
        after.endSpan()
        toastMessage = "OK: 2nd global rejected; new global after endSpan works"
    }

    private func runWithContextNetwork() {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { toastMessage = "SDK not initialized"; return }
        guard let tracer = tracerForSession(preferIgnored: false) else { return }
        guard let global = tracer.startGlobalSpan(name: "demo.custom.with_context", labels: ["demo.flow": "network"]) else {
            toastMessage = "startGlobalSpan returned nil"
            return
        }
        global.withContext { NetworkSim.sendSuccesfullRequest() }
        global.endSpan()
        toastMessage = "GET started under withContext; global span ended"
    }
}
