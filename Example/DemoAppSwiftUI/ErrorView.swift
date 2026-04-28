import SwiftUI

struct ErrorView: View {
    @State private var toastMessage: String?

    private struct Item {
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }

    private var items: [Item] {
        [
            Item(title: "NSException",
                 subtitle: "Send NSException error",
                 icon: "exclamationmark.triangle",
                 action: { ErrorSim.sendNSException() }),
            Item(title: "NSError",
                 subtitle: "Send NSError error",
                 icon: "exclamationmark.circle",
                 action: { ErrorSim.sendNSError() }),
            Item(title: "Error",
                 subtitle: "Send Swift Error",
                 icon: "xmark.circle",
                 action: { ErrorSim.sendError() }),
            Item(title: "Message Data Error",
                 subtitle: "Custom log with error message",
                 icon: "doc.text",
                 action: { ErrorSim.sendMessageDataError() }),
            Item(title: "Stack Trace Error",
                 subtitle: "Error with stack trace and type",
                 icon: "list.bullet.rectangle",
                 action: { ErrorSim.sendMessageStackTraceTypeIsCarshError() }),
            Item(title: "Log Error",
                 subtitle: "Send error via logging",
                 icon: "doc.append",
                 action: { ErrorSim.sendErrorLog() }),
            Item(title: "Crash",
                 subtitle: "Simulate a random crash",
                 icon: "bolt.trianglebadge.exclamationmark",
                 action: { CrashSim.simulateRandomCrash() }),
            Item(title: "Simulate ANR",
                 subtitle: "Application Not Responding",
                 icon: "hourglass",
                 action: { ErrorSim.simulateANR() }),
            Item(title: "Flutter Symbolicated Error",
                 subtitle: "Simulate readable Dart stack trace",
                 icon: "curlybraces",
                 action: { ErrorSim.sendFlutterSymbolicatedError() }),
            Item(title: "Flutter Obfuscated Error",
                 subtitle: "Simulate obfuscated Dart stack trace (virt addresses)",
                 icon: "eye.slash",
                 action: { ErrorSim.sendFlutterObfuscatedError() })
        ]
    }

    var body: some View {
        List {
            ForEach(items, id: \.title) { item in
                Button {
                    toastMessage = "Selected: \(item.title)"
                    item.action()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.body)
                                .foregroundColor(.primary)
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
        .navigationTitle("Error instrumentation")
        .navigationBarTitleDisplayMode(.large)
        .trackCXView(name: "Error instrumentation")
        .toast(message: $toastMessage)
    }
}
