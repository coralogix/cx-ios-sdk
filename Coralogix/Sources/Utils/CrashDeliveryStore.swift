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
    /// Sent in this order, as Android sends native crashes before ANRs.
    enum Kind: String, Codable {
        case native
        /// A hang the process ended during (`FatalHangRecovery`).
        case anr
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
    /// One file per stored fatal hang (`<crash id>.json`), as `copiesDirectory` holds crashes.
    let hangsDirectory: URL
    /// Written while the watchdog sees the main thread hung, and cleared when it answers again.
    let hangMarkerFile: URL
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
        self.hangsDirectory = folder.appendingPathComponent("hangs", isDirectory: true)
        self.hangMarkerFile = folder.appendingPathComponent("anr-in-progress.json")
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

    // MARK: - Fatal hangs

    /// The stored fatal hang files.
    func hangs() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: hangsDirectory,
                                                                   includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
    }

    /// Keeps `marker` as a hang to send, under its crash id. Returns where, or nil if it could not be written.
    func storeHang(_ marker: HangMarker) -> URL? {
        let url = hangsDirectory.appendingPathComponent("\(marker.crashId).json")
        do {
            try FileManager.default.createDirectory(at: hangsDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(marker).write(to: url, options: .atomic)
            return url
        } catch {
            Log.e("[CrashDeliveryStore] Failed to store a fatal hang: \(error)")
            return nil
        }
    }

    func writeHangMarker(_ marker: HangMarker) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: hangMarkerFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(marker).write(to: hangMarkerFile, options: .atomic)
        } catch {
            Log.e("[CrashDeliveryStore] Failed to write the hang marker: \(error)")
        }
    }

    /// The marker a hang left, if any. nil too when it cannot be read yet; a corrupt one is deleted.
    func hangMarker() -> HangMarker? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: hangMarkerFile) else { return nil }
        guard let marker = try? JSONDecoder().decode(HangMarker.self, from: data) else {
            try? FileManager.default.removeItem(at: hangMarkerFile)
            return nil
        }
        return marker
    }

    func clearHangMarker() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: hangMarkerFile)
    }

    /// Notes that the hang `crashId` was reported by its own event, if its marker is still there.
    func markHangDelivered(crashId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: hangMarkerFile),
              var marker = try? JSONDecoder().decode(HangMarker.self, from: data),
              marker.crashId == crashId, !marker.liveDelivered else { return }
        marker.liveDelivered = true
        try? JSONEncoder().encode(marker).write(to: hangMarkerFile, options: .atomic)
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
