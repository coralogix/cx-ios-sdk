//
//  E2EHooks.swift
//  CrashE2EApp
//
//  Test hooks applied to the SDK's own files before CoralogixRum is initialized: the iOS stand-ins
//  for Android's fresh install, `recordFailedUploads` and `dateCrash`, and for a device still locked
//  when the app launches (`lockCrashCopies`). They read and edit the
//  delivery store's JSON, which pins its format in this repo; they exist only in this test host.
//

import Foundation
import Security

enum E2EHooks {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    static var sdkDirectory: URL { supportDirectory.appendingPathComponent("CoralogixRum", isDirectory: true) }
    static var recordsFile: URL { sdkDirectory.appendingPathComponent("crash_delivery.json") }
    static var copiesDirectory: URL { sdkDirectory.appendingPathComponent("crashes", isDirectory: true) }
    static var plCrashReporterDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.plausiblelabs.crashreporter.data")
    }

    static func apply(_ hooks: [String]) {
        for hook in hooks {
            let parts = hook.split(separator: ":", maxSplits: 1).map(String.init)
            let argument = parts.count > 1 ? Double(parts[1]) : nil
            switch parts[0] {
            case "reset": reset()
            case "setFailedUploads": editRecords { $0["failedUploads"] = Int(argument ?? 0) }
            case "ageCrashesBySeconds":
                editRecords { record in
                    // Codable's default date: seconds since the reference date.
                    if let time = record["crashTime"] as? Double { record["crashTime"] = time - (argument ?? 0) }
                }
            case "seedLegacyHybridStore": seedLegacyHybridStore()
            case "lockCrashCopies": lockCrashCopies()
            case "unlockCrashCopies": setPermissions(0o644, ofFilesIn: copiesDirectory)
            default: NSLog("[CrashE2E] unknown hook %@", hook)
            }
        }
    }

    /// A fresh install as far as the SDK can tell: its files, PLCrashReporter's and its keychain items.
    /// Files only: PLCrashReporter was enabled at image load, before this runs, and writes a crash of
    /// this launch into its directory, which must still be there.
    private static func reset() {
        removeFiles(in: sdkDirectory)
        removeFiles(in: plCrashReporterDirectory)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword] as CFDictionary)
    }

    private static func removeFiles(in directory: URL) {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        while let file = files?.nextObject() as? URL {
            let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// The crash copies cannot be read this launch, as before the first unlock: the files are
    /// listed, their contents refused. The image-load copy of PLCrashReporter's pending report is
    /// already made, so the report is removed too: recovery would otherwise copy it again,
    /// readable, over the locked copy.
    private static func lockCrashCopies() {
        removeFiles(in: plCrashReporterDirectory)
        setPermissions(0o000, ofFilesIn: copiesDirectory)
    }

    private static func setPermissions(_ permissions: Int, ofFilesIn directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        }
    }

    private static func editRecords(_ edit: (inout [String: Any]) -> Void) {
        guard let data = try? Data(contentsOf: recordsFile),
              var records = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
        for key in records.keys {
            if var record = records[key] {
                edit(&record)
                records[key] = record
            }
        }
        if let edited = try? JSONSerialization.data(withJSONObject: records) {
            try? edited.write(to: recordsFile, options: .atomic)
        }
    }

    /// A crash event as 2.22 kept it for re-sending: the new version deletes it unsent.
    private static func seedLegacyHybridStore() {
        try? FileManager.default.createDirectory(at: sdkDirectory, withIntermediateDirectories: true)
        let legacy = #"[{"error_message":"legacy hybrid crash","store_event_id":"legacy-1"}]"#
        try? Data(legacy.utf8).write(to: sdkDirectory.appendingPathComponent("pending_crash_events.json"))
    }

    /// The stored crashes as the test reads them: id, kind and counted failures, sorted by id.
    static func storedCrashes() -> String {
        guard let data = try? Data(contentsOf: recordsFile),
              let records = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return "[]" }
        let summary = records.keys.sorted().map { id -> [String: Any] in
            let record = records[id] ?? [:]
            return ["id": id, "kind": record["kind"] ?? "", "failedUploads": record["failedUploads"] ?? 0]
        }
        let json = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
        return json.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
