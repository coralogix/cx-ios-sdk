//
//  AppDelegate.swift
//  CrashE2EApp
//
//  The host app the crash e2e suite drives, like Android's crash-app: it links the SDK only, so
//  the demo apps' own events and instrumentation do not get in the way. Each launch follows the
//  scenario the test passes in (`Scenario`).
//

import UIKit
import Coralogix
import SessionReplay

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    static private(set) var sdk: CoralogixRum?
    static private(set) var scenario = Scenario()
    /// Kept for the life of the process: a global span is ended once nothing holds it.
    static private(set) var globalSpan: CoralogixGlobalSpan?
    static var globalTraceId: String? { globalSpan?.traceId }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let scenario = Scenario.current()
        Self.scenario = scenario
        E2EHooks.apply(scenario.hooks)

        let start = scenario.appStart.split(separator: ":", maxSplits: 1).map(String.init)
        if start[0] == "crashBeforeInit" {
            E2ECrashes.crash(start.count > 1 ? start[1] : "signal")
        }
        if start[0] != "withoutSdk" {
            Self.sdk = Self.initialize(scenario)
        }
        if start[0] == "crashAfterInit" {
            E2ECrashes.crash(start.count > 1 ? start[1] : "signal")
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: HomeViewController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    private static func initialize(_ scenario: Scenario) -> CoralogixRum {
        var options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            environment: "e2e",
            application: "CrashE2E",
            version: scenario.appVersion,
            publicKey: "crash-e2e-key",
            ignoreErrors: scenario.ignoreErrors,
            sessionSampleRate: scenario.sessionSampleRate,
            instrumentations: [.errors: scenario.errorInstrumentation,
                               .anr: scenario.anrInstrumentation,
                               .userActions: true,
                               .custom: scenario.globalSpan,
                               .lifeCycle: false,
                               .network: false,
                               .mobileVitals: false],
            beforeSend: { event in crashBeforeSend(event, scenario.crashBeforeSend) },
            proxyUrl: scenario.proxyUrl,
            // The custom tracer, which starts a global span, needs it.
            traceParentInHeader: scenario.globalSpan ? ["enable": true] : nil,
            debug: true)
        if scenario.tracesExporter {
            options.tracesExporter = { data in
                // Crash spans carry crash_event_id among their attributes.
                let crashes = (data.jsonString?.components(separatedBy: "crash_event_id").count ?? 1) - 1
                ForwardedCrashes.add(crashes)
            }
        }
        if scenario.hybridBeforeSend {
            // A hybrid wrapper's round trip: every event it is given comes back, edited or not.
            let edits = scenario.hybridEdit
            options.beforeSendCallBack = { events in
                AppDelegate.sdk?.sendBeforeSendData(edits ? events.map(hybridEdited) : events)
            }
        }
        let sdk = CoralogixRum(options: options,
                               sdkFramework: scenario.hybridBeforeSend ? .reactNative(version: "e2e") : .swift)
        if scenario.globalSpan {
            globalSpan = sdk.getCustomTracer()?.startGlobalSpan(name: "crash-e2e-global-span")
        }
        if scenario.sessionReplay {
            SessionReplay.initializeWithOptions(sessionReplayOptions: SessionReplayOptions(
                recordingType: .image, captureScale: 1, captureCompressionQuality: 0.5,
                maskText: nil, maskOnlyCreditCards: false, maskAllImages: false, autoStartSessionRecording: true))
        }
        return sdk
    }

    private static func hybridEdited(_ event: [String: Any]) -> [String: Any] {
        if var error = event["error_context"] as? [String: Any] {
            error["error_message"] = Scenario.hybridEditedMessage
            var edited = event
            edited["error_context"] = error
            return edited
        }
        guard var text = event["text"] as? [String: Any], var cxRum = text["cx_rum"] as? [String: Any],
              var error = cxRum["error_context"] as? [String: Any] else { return event }
        error["error_message"] = Scenario.hybridEditedMessage
        cxRum["error_context"] = error
        text["cx_rum"] = cxRum
        var edited = event
        edited["text"] = text
        return edited
    }

    private static func crashBeforeSend(_ event: [String: Any], _ rule: String) -> [String: Any]? {
        guard var error = event["error_context"] as? [String: Any], error["is_crash"] as? Bool == true else {
            return event
        }
        switch rule {
        case "drop":
            return nil
        case "edit":
            error["error_message"] = Scenario.editedMessage
            var edited = event
            edited["error_context"] = error
            return edited
        default:
            return event
        }
    }
}

/// How many crash spans `tracesExporter` received in this process, for the test to read.
enum ForwardedCrashes {
    private static let lock = NSLock()
    private static var _count = 0
    static var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    static func add(_ n: Int) { lock.lock(); _count += n; lock.unlock() }
}
