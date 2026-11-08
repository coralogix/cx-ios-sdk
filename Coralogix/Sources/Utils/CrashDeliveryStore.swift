//
//  CrashDeliveryStore.swift
//  Coralogix
//

import Foundation
import CoralogixInternal
#if canImport(CoralogixBootstrap)
import CoralogixBootstrap
#endif

/// One stored crash as every send of it reports it: the session it happened in, that session's
/// view, counters and versions at the time, and how its delivery has gone so far. Written once,
/// on the first launch that reads the crash, so a launch later still reports the same thing.
struct StoredCrashRecord: Codable, Equatable {
    enum Kind: String, Codable {
        case native
    }

    struct Session: Codable, Equatable {
        let id: String
        /// nil for a session seeded at image load that the SDK never adopted.
        let creationDate: TimeInterval?
        let sampledIn: Bool?
    }

    let crashId: String
    let kind: Kind
    let crashTime: Date
    var failedUploads: Int
    let session: Session
    /// The crashed session's counters at the crash. Never incremented in place: each send reports
    /// them with its own error added.
    let counters: SessionSnapshotRecord
}

extension StoredCrashRecord {
    /// The counters a send reports: the crashed session's, plus this crash.
    var reportedCounters: SessionSnapshotRecord {
        var counters = self.counters
        counters.errorCount += 1
        return counters
    }
}

/// The SDK's own copies of crash reports, and the delivery record of each.
///
/// PLCrashReporter keeps one pending report; `CRXCrashBootstrap` moves it into `copiesDirectory`
/// at image load, so a crash a launch could not deliver is not lost to the next one. Recovery
/// reads only the copies.
final class CrashDeliveryStore {
    /// At most this many crashes of a kind are kept, the newest.
    static let maxPerKind = 10

    let copiesDirectory: URL
    private let recordsFile: URL
    private let legacyHybridStoreFile: URL
    private let lock = NSLock()

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("CoralogixRum", isDirectory: true)
        let ownCopies = folder.appendingPathComponent("crashes", isDirectory: true)
        // The bootstrap writes the copies at image load, so by default its directory is the one.
        self.copiesDirectory = directory == nil ? (CRXCrashBootstrap.crashCopiesDirectory ?? ownCopies) : ownCopies
        self.recordsFile = folder.appendingPathComponent("crash_delivery.json")
        self.legacyHybridStoreFile = folder.appendingPathComponent("pending_crash_events.json")
    }

    // MARK: - Report copies

    /// The stored report files. A directory that does not exist yet holds none.
    func copies() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: copiesDirectory,
                                                                   includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "plcrash" }
    }

    func removeCopy(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Delivery records

    func record(for crashId: String) -> StoredCrashRecord? {
        lock.lock()
        defer { lock.unlock() }
        return readLocked()?[crashId]
    }

    func save(_ record: StoredCrashRecord) {
        mutate { $0[record.crashId] = record }
    }

    func countFailedUpload(of crashId: String) {
        mutate { $0[crashId]?.failedUploads += 1 }
    }

    func removeRecord(for crashId: String) {
        mutate { $0.removeValue(forKey: crashId) }
    }

    /// Reads, changes and writes the records under one lock. A file that exists but cannot be read
    /// — data protection before the first unlock, typically — is left alone rather than replaced:
    /// it is not corrupt, and writing over it would lose every other crash's record.
    private func mutate(_ change: (inout [String: StoredCrashRecord]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard var records = readLocked() else { return }
        change(&records)
        writeLocked(records)
    }

    /// nil when the file exists but could not be read; empty when there is none, or it is corrupt.
    private func readLocked() -> [String: StoredCrashRecord]? {
        guard FileManager.default.fileExists(atPath: recordsFile.path) else { return [:] }
        guard let data = try? Data(contentsOf: recordsFile) else { return nil }
        return (try? JSONDecoder().decode([String: StoredCrashRecord].self, from: data)) ?? [:]
    }

    private func writeLocked(_ records: [String: StoredCrashRecord]) {
        do {
            try FileManager.default.createDirectory(at: recordsFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: recordsFile, options: .atomic)
        } catch {
            Log.e("[CrashDeliveryStore] Failed to write crash delivery records: \(error)")
        }
    }

    // MARK: - Migration

    /// Earlier versions kept hybrid crash events in a file of their own and re-sent them. Hybrid
    /// crashes are now sent once, live; what that file still holds is deleted, not sent.
    func deleteLegacyHybridStore() {
        try? FileManager.default.removeItem(at: legacyHybridStoreFile)
    }
}
