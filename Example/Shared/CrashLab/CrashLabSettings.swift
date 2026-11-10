//
//  CrashLabSettings.swift
//  DemoApp
//
//  What the next launches of the demo app do, for the Crash Lab. Kept as JSON in Application
//  Support, where both the lab screen and the driver script (`tool/crash-lab/run_crash_lab.py`)
//  write it, and read once before the SDK is initialized: a change applies at the next launch.
//  Keys match the Android lab's where they exist. Every setting starts at its first value, which
//  is the demo app's normal behaviour.
//

import Foundation
import Coralogix
import CoralogixInternal
import SessionReplay

/// One preset value of a setting. JSON-shaped, so the driver can write it.
enum CrashLabValue: Equatable, CustomStringConvertible {
    case none
    case bool(Bool)
    case int(Int)
    case string(String)

    init(json: Any?) {
        switch json {
        case let value as Bool: self = .bool(value)
        case let value as Int: self = .int(value)
        case let value as String: self = .string(value)
        default: self = .none
        }
    }

    var json: Any {
        switch self {
        case .none: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .string(let value): return value
        }
    }

    var description: String {
        switch self {
        case .none: return "—"
        case .bool(let value): return value ? "on" : "off"
        case .int(let value): return "\(value)"
        case .string(let value): return value
        }
    }
}

enum CrashLabSetting: String, CaseIterable {
    case coralogixEnv, sdkDebug, crashBeforeInit, launchAction, launchActionCount, sessionSampleRate
    case errorInstrumentation, anrInstrumentation, ignoreErrors, crashBeforeSend, tracesExporter
    case appVersion, endpoint, sessionReplay, globalSpan, hybridBeforeSend

    var key: String { rawValue }

    var label: String {
        switch self {
        case .coralogixEnv: return "Coralogix environment (— : the demo app's)"
        case .sdkDebug: return "SDK debug logging"
        case .crashBeforeInit: return "Crash before init (next launch only)"
        case .launchAction: return "Right after init: crash or hang"
        case .launchActionCount: return "Launches the action above repeats for"
        case .sessionSampleRate: return "sessionSampleRate"
        case .errorInstrumentation: return "Instrumentation .errors"
        case .anrInstrumentation: return "Instrumentation .anr"
        case .ignoreErrors: return "ignoreErrors"
        case .crashBeforeSend: return "What beforeSend does to a crash"
        case .tracesExporter: return "tracesExporter (logs each forwarded span)"
        case .appVersion: return "App version reported (— : the demo app's)"
        case .endpoint: return "Endpoint (mock: http://127.0.0.1:<mockPort>)"
        case .sessionReplay: return "Start session recording at launch"
        case .globalSpan: return "Start a global span at launch"
        case .hybridBeforeSend: return "Hybrid SDK with a beforeSend round trip"
        }
    }

    var values: [CrashLabValue] {
        switch self {
        case .coralogixEnv: return [.none, .string(CrashLabSettings.eu1CrashLab)]
        case .sdkDebug, .tracesExporter, .sessionReplay, .globalSpan, .hybridBeforeSend: return [.bool(false), .bool(true)]
        case .crashBeforeInit: return [.none, .string("exception"), .string("signal")]
        case .launchAction: return [.none, .string("exception"), .string("signal"), .string("cxx"), .string("hang")]
        case .launchActionCount: return [.int(1), .int(3), .int(12)]
        case .sessionSampleRate: return [.int(100), .int(0)]
        case .errorInstrumentation, .anrInstrumentation: return [.bool(true), .bool(false)]
        case .ignoreErrors:
            return [.none, .string("SIGSEGV.*"), .string("NSInvalidArgumentException:.*"), .string("ANR")]
        case .crashBeforeSend: return [.string("keep"), .string("drop"), .string("edit")]
        case .appVersion: return [.none, .string("crashlab-old"), .string("crashlab-new")]
        case .endpoint: return [.none, .string("mock")]
        }
    }
}

final class CrashLabSettings {
    static let fileName = "crash_lab.json"
    static let eu1CrashLab = "eu1-crash-lab"
    static let editedMessage = "edited in beforeSend"
    static let hangSeconds: TimeInterval = 60
    /// Free-text keys the driver may write: the EU1 lab environment's key, never committed, and
    /// the mock endpoint's port.
    static let publicKeyKey = "publicKey"
    static let mockPortKey = "mockPort"

    static let shared = CrashLabSettings()

    let file: URL
    private let lock = NSLock()
    private var json: [String: Any]

    init(file: URL = CrashLabSettings.defaultFile) {
        self.file = file
        let data = try? Data(contentsOf: file)
        self.json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent(fileName)
    }

    subscript(setting: CrashLabSetting) -> CrashLabValue {
        get {
            lock.lock()
            defer { lock.unlock() }
            guard let stored = json[setting.key], !(stored is NSNull) else { return setting.values[0] }
            return CrashLabValue(json: stored)
        }
        set {
            lock.lock()
            if newValue == setting.values[0] {
                json.removeValue(forKey: setting.key)
            } else {
                json[setting.key] = newValue.json
            }
            // Synchronous: a one-shot is consumed before the crash it arms, or it would crash every launch.
            write()
            lock.unlock()
        }
    }

    /// Moves `setting` to its next preset value.
    func cycle(_ setting: CrashLabSetting) {
        let values = setting.values
        let index = values.firstIndex(of: self[setting]) ?? 0
        self[setting] = values[(index + 1) % values.count]
    }

    func reset() {
        lock.lock()
        CrashLabSetting.allCases.forEach { json.removeValue(forKey: $0.key) }
        write()
        lock.unlock()
    }

    private func write() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func flag(_ setting: CrashLabSetting) -> Bool { self[setting] == .bool(true) }

    private func string(_ setting: CrashLabSetting) -> String? {
        if case .string(let value) = self[setting] { return value }
        return nil
    }

    private func freeText(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return json[key] as? String
    }

    // MARK: - Applying

    /// Called first, before the SDK is initialized.
    func beforeInit() {
        guard let crash = string(.crashBeforeInit) else { return }
        self[.crashBeforeInit] = .none
        CrashLabTriggers.crash(kind: crash, message: "crash lab: crash before the SDK is initialized")
    }

    var domain: CoralogixDomain? { string(.coralogixEnv) == Self.eu1CrashLab ? .EU1 : nil }
    var publicKey: String? { domain == nil ? nil : freeText(Self.publicKeyKey) }
    var debug: Bool { flag(.sdkDebug) }
    var appVersion: String? { string(.appVersion) }
    var sessionSampleRate: Int {
        if case .int(let rate) = self[.sessionSampleRate] { return rate }
        return 100
    }
    var ignoreErrors: [String]? { string(.ignoreErrors).map { [$0] } }
    var isHybrid: Bool { flag(.hybridBeforeSend) }
    var tracesExporterOn: Bool { flag(.tracesExporter) }

    var proxyUrl: String? {
        guard string(.endpoint) == "mock" else { return nil }
        return "http://127.0.0.1:\(freeText(Self.mockPortKey) ?? "8080")"
    }

    func instrumentations(_ base: [CoralogixExporterOptions.InstrumentationType: Bool]) -> [CoralogixExporterOptions.InstrumentationType: Bool] {
        var instrumentations = base
        instrumentations[.errors] = flag(.errorInstrumentation)
        instrumentations[.anr] = flag(.anrInstrumentation)
        return instrumentations
    }

    /// The app's own `beforeSend`, after what this lab does to crashes.
    func beforeSend(wrapping appBeforeSend: (([String: Any]) -> [String: Any]?)?) -> ([String: Any]) -> [String: Any]? {
        return { [weak self] event in
            guard let edited = self?.crashBeforeSend(event) else { return nil }
            return appBeforeSend?(edited) ?? edited
        }
    }

    private func crashBeforeSend(_ event: [String: Any]) -> [String: Any]? {
        guard var error = event[CoralogixInternal.Keys.errorContext.rawValue] as? [String: Any],
              error[CoralogixInternal.Keys.isCrash.rawValue] as? Bool == true else { return event }
        switch string(.crashBeforeSend) {
        case "drop":
            return nil
        case "edit":
            error[CoralogixInternal.Keys.errorMessage.rawValue] = Self.editedMessage
            var edited = event
            edited[CoralogixInternal.Keys.errorContext.rawValue] = error
            return edited
        default:
            return event
        }
    }

    /// Called last, once the SDK is initialized.
    func afterInit(sdk: CoralogixRum) {
        // The driver script reads this to know which session each launch is.
        NSLog("[CrashLab] launch session=%@", sdk.getSessionId ?? "none")
        if flag(.sessionReplay) {
            // Next turn: the demo apps initialize session replay after the SDK.
            DispatchQueue.main.async { SessionReplay.shared?.startRecording() }
        }
        if flag(.globalSpan) {
            _ = sdk.getCustomTracer()?.startGlobalSpan(name: "crash-lab-global-span")
        }
        guard let action = string(.launchAction) else { return }
        if case .int(let count) = self[.launchActionCount], count > 1 {
            self[.launchActionCount] = .int(count - 1)
        } else {
            self[.launchAction] = .none
            self[.launchActionCount] = .int(1)
        }
        if action == "hang" {
            // Posted, so it blocks the main thread as the first screen is about to show.
            DispatchQueue.main.async { Thread.sleep(forTimeInterval: Self.hangSeconds) }
        } else {
            CrashLabTriggers.crash(kind: action, message: "crash lab: launch crash")
        }
    }

    /// `-crashLabCase <id>` among the launch arguments: the driver's way to run one case.
    static var launchCase: String? {
        UserDefaults.standard.string(forKey: "crashLabCase")
    }
}
