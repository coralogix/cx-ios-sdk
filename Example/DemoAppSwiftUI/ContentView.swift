import SwiftUI
import Coralogix

struct ContentView: View {
    @State private var toastMessage: String?
    @State private var sessionID: String = CoralogixRumManager.shared.getSessionId()?.lowercased() ?? "No session"

    private struct MenuItem {
        let title: String
        let subtitle: String
        let icon: String
        let destination: AnyView
    }

    private var menuItems: [MenuItem] {
        [
            MenuItem(
                title: "Network instrumentation",
                subtitle: "Track requests, responses & timings",
                icon: "antenna.radiowaves.left.and.right",
                destination: AnyView(NetworkView())
            ),
            MenuItem(
                title: "Error instrumentation",
                subtitle: "Capture crashes, errors & exceptions",
                icon: "exclamationmark.triangle",
                destination: AnyView(ErrorView())
            ),
            MenuItem(
                title: "SDK functions",
                subtitle: "Test core Coralogix APIs",
                icon: "gearshape",
                destination: AnyView(SdkView())
            ),
            MenuItem(
                title: "Custom spans",
                subtitle: "Manual global & nested spans (Browser API parity)",
                icon: "timeline.selection",
                destination: AnyView(CustomSpansView())
            ),
            MenuItem(
                title: "User actions",
                subtitle: "Buttons, screens & custom events",
                icon: "hand.tap",
                destination: AnyView(UserActionsView())
            ),
            MenuItem(
                title: "Session replay",
                subtitle: "Replay user sessions visually",
                icon: "film.stack",
                destination: AnyView(SessionReplayView())
            ),
            MenuItem(
                title: "Clock",
                subtitle: "Timing, spans & scheduling",
                icon: "clock",
                destination: AnyView(ClockView())
            ),
            MenuItem(
                title: "Schema validation",
                subtitle: "Validate payload structure & fields",
                icon: "checkmark.shield",
                destination: AnyView(SchemaValidationView())
            ),
            MenuItem(
                title: "Mask UI",
                subtitle: "Hide sensitive on-screen data",
                icon: "eye.slash",
                destination: AnyView(MaskDemoView())
            ),
            MenuItem(
                title: "Traces Exporter",
                subtitle: "Test OTLP trace export callback",
                icon: "arrow.up.doc",
                destination: AnyView(TracesExporterView())
            )
        ]
    }

    var body: some View {
        NavigationView {
            List {
                sessionHeader

                swipeDemo

                ForEach(menuItems, id: \.title) { item in
                    NavigationLink(destination: item.destination) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.body)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: item.icon)
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 28)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Coralogix Demo")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        copySessionID()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
            .trackCXView(name: "Main View")
            .onAppear {
                CoralogixRumManager.shared.sdk.setUserContext(
                    userContext: UserContext(
                        userId: "1234",
                        userName: "Daffy Duck",
                        userEmail: "daffy.duck@coralogix.com",
                        userMetadata: ["age": "18", "profession": "duck"]
                    )
                )
            }
        }
        .toast(message: $toastMessage)
    }

    @SwiftUI.ViewBuilder
    private var sessionHeader: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session ID")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(sessionID)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.primary)
                }
                Spacer()
                Button("Copy") {
                    copySessionID()
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var swipeDemo: some View {
        Section("Swipe Demo") {
            VStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .trackCXSwipeAction()
                Text("Swipe the icon to emit a RUM swipe span")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
        }
    }

    private func copySessionID() {
        guard let id = CoralogixRumManager.shared.getSessionId() else {
            toastMessage = "No session ID available"
            return
        }
        UIPasteboard.general.string = id
        toastMessage = "Session ID copied"
    }
}
