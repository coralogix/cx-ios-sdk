import SwiftUI

struct ErrorView: View {
    var body: some View {
        ActionListView(
            title: "Error instrumentation",
            cxViewName: "Error instrumentation",
            items: [
                ActionItem(title: "NSException",
                           subtitle: "Send NSException error",
                           icon: "exclamationmark.triangle",
                           action: { ErrorSim.sendNSException() }),
                ActionItem(title: "NSError",
                           subtitle: "Send NSError error",
                           icon: "exclamationmark.circle",
                           action: { ErrorSim.sendNSError() }),
                ActionItem(title: "Error",
                           subtitle: "Send Swift Error",
                           icon: "xmark.circle",
                           action: { ErrorSim.sendError() }),
                ActionItem(title: "Message Data Error",
                           subtitle: "Custom log with error message",
                           icon: "doc.text",
                           action: { ErrorSim.sendMessageDataError() }),
                ActionItem(title: "Stack Trace Error",
                           subtitle: "Error with stack trace and type",
                           icon: "list.bullet.rectangle",
                           action: { ErrorSim.sendMessageStackTraceTypeIsCarshError() }),
                ActionItem(title: "Log Error",
                           subtitle: "Send error via logging",
                           icon: "doc.append",
                           action: { ErrorSim.sendErrorLog() }),
                ActionItem(title: "Crash",
                           subtitle: "Simulate a random crash",
                           icon: "bolt.trianglebadge.exclamationmark",
                           action: { CrashSim.simulateRandomCrash() }),
                ActionItem(title: "Simulate ANR",
                           subtitle: "Application Not Responding",
                           icon: "hourglass",
                           action: { ErrorSim.simulateANR() }),
                ActionItem(title: "Flutter Symbolicated Error",
                           subtitle: "Simulate readable Dart stack trace",
                           icon: "curlybraces",
                           action: { ErrorSim.sendFlutterSymbolicatedError() }),
                ActionItem(title: "Flutter Obfuscated Error",
                           subtitle: "Simulate obfuscated Dart stack trace (virt addresses)",
                           icon: "eye.slash",
                           action: { ErrorSim.sendFlutterObfuscatedError() })
            ]
        )
    }
}
