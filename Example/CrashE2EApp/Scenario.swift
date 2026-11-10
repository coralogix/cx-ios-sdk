//
//  Scenario.swift
//  CrashE2EApp
//
//  What one launch of the e2e host app does, as the UI test passes it in
//  `launchEnvironment["CX_E2E_SCENARIO"]` (JSON). Mirrors the Android crash-e2e app's scenario.
//  The configuration is kept in Application Support, so a launch without the variable reuses the
//  last one; the one-shot parts (hooks, actions, a crash at start) are never kept.
//

import Foundation

struct Scenario: Codable {
    /// Where the SDK sends: the test's endpoint.
    var proxyUrl: String?
    /// `initialize`, `crashAfterInit:<kind>`, `crashBeforeInit:<kind>` or `withoutSdk`.
    var appStart: String = "initialize"
    /// Run in order once the first screen is up: a crash kind (`crash:<kind>`), `hang:<ms>`,
    /// `hangForever`, `rotate`, `view:Second`, `clicks:<n>`, `hybridCrash`, `wait:<ms>`.
    var actions: [String] = []
    var appVersion: String = "1.0"
    var sessionSampleRate: Int = 100
    var ignoreErrors: [String] = []
    var errorInstrumentation: Bool = true
    var anrInstrumentation: Bool = true
    /// What the native beforeSend does to a crash: `keep`, `drop` or `edit`.
    var crashBeforeSend: String = "keep"
    var tracesExporter: Bool = false
    var hybridBeforeSend: Bool = false
    /// The hybrid beforeSend replaces every error message it sees with `hybridEditedMessage`.
    var hybridEdit: Bool = false
    var globalSpan: Bool = false
    var sessionReplay: Bool = false
    /// Applied to the SDK's files before init: `reset`, `setFailedUploads:<n>`,
    /// `ageCrashesBySeconds:<s>`, `seedLegacyHybridStore`.
    var hooks: [String] = []

    static let environmentKey = "CX_E2E_SCENARIO"
    static let editedMessage = "edited in beforeSend"
    static let hybridEditedMessage = "edited in hybrid beforeSend"

    private static var file: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("crash_e2e_scenario.json")
    }

    /// This launch's scenario: the one passed in, else the last one kept, else the defaults.
    static func current() -> Scenario {
        let decoder = JSONDecoder()
        if let json = ProcessInfo.processInfo.environment[environmentKey],
           let scenario = try? decoder.decode(Scenario.self, from: Data(json.utf8)) {
            scenario.keep()
            return scenario
        }
        if let data = try? Data(contentsOf: file), let scenario = try? decoder.decode(Scenario.self, from: data) {
            return scenario
        }
        return Scenario()
    }

    private func keep() {
        var kept = self
        kept.hooks = []
        kept.actions = []
        kept.appStart = "initialize"
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(kept).write(to: Self.file, options: .atomic)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxyUrl = try c.decodeIfPresent(String.self, forKey: .proxyUrl)
        appStart = try c.decodeIfPresent(String.self, forKey: .appStart) ?? appStart
        actions = try c.decodeIfPresent([String].self, forKey: .actions) ?? actions
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? appVersion
        sessionSampleRate = try c.decodeIfPresent(Int.self, forKey: .sessionSampleRate) ?? sessionSampleRate
        ignoreErrors = try c.decodeIfPresent([String].self, forKey: .ignoreErrors) ?? ignoreErrors
        errorInstrumentation = try c.decodeIfPresent(Bool.self, forKey: .errorInstrumentation) ?? errorInstrumentation
        anrInstrumentation = try c.decodeIfPresent(Bool.self, forKey: .anrInstrumentation) ?? anrInstrumentation
        crashBeforeSend = try c.decodeIfPresent(String.self, forKey: .crashBeforeSend) ?? crashBeforeSend
        tracesExporter = try c.decodeIfPresent(Bool.self, forKey: .tracesExporter) ?? tracesExporter
        hybridBeforeSend = try c.decodeIfPresent(Bool.self, forKey: .hybridBeforeSend) ?? hybridBeforeSend
        hybridEdit = try c.decodeIfPresent(Bool.self, forKey: .hybridEdit) ?? hybridEdit
        globalSpan = try c.decodeIfPresent(Bool.self, forKey: .globalSpan) ?? globalSpan
        sessionReplay = try c.decodeIfPresent(Bool.self, forKey: .sessionReplay) ?? sessionReplay
        hooks = try c.decodeIfPresent([String].self, forKey: .hooks) ?? hooks
    }
}
