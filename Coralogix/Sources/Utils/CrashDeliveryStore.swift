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
/// PLCrashReporter keeps one pending report; `CRXCrashBootstrap` copies it into `copiesDirectory`
/// at image load, and recovery empties the slot once it reports crashes, so a crash a launch could
/// not deliver is not lost to the next one. Recovery reads only the copies.
final class CrashDeliveryStore {
    /// At most this many crashes of a kind are kept, the newest.
    static let maxPerKind = 10

    /// Where the SDK keeps its files, as `CRXCrashBootstrap.crashCopiesDirectory` does: tvOS gives
    /// apps no persistent storage beyond caches.
    #if os(tvOS)
    static let baseDirectory = FileManager.SearchPathDirectory.cachesDirectory
    #else
    static let baseDirectory = FileManager.SearchPathDirectory.applicationSupportDirectory
    #endif

    /// Where the SDK keeps its files when no directory is passed in.
    static var defaultFolder: URL {
        let base = FileManager.default.urls(for: baseDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return folder(in: base)
    }

    private static func folder(in base: URL) -> URL {
        base.appendingPathComponent("CoralogixRum", isDirectory: true)
    }

    static func snapshotsDirectory(in folder: URL) -> URL {
        folder.appendingPathComponent("sessions", isDirectory: true)
    }

    let copiesDirectory: URL
    /// The session record of each launch (`SessionSnapshotStore`), which a crash read for the
    /// first time is attributed with.
    let snapshotsDirectory: URL
    /// One file per stored fatal hang (`<crash id>.json`), as `copiesDirectory` holds crashes.
    let hangsDirectory: URL
    /// Written while the watchdog sees the main thread hung, and cleared when it answers again.
    let hangMarkerFile: URL
    private let recordsFile: URL
    private let legacyHybridStoreFile: URL
    /// Shared by every instance: each `CoralogixRum` has its own store, and all of them read, change
    /// and write the same records file.
    private static let lock = NSLock()

    init(directory: URL? = nil) {
        let folder = directory.map(Self.folder(in:)) ?? Self.defaultFolder
        let ownCopies = folder.appendingPathComponent("crashes", isDirectory: true)
        // The bootstrap writes the copies at image load, so by default its directory is the one.
        self.copiesDirectory = directory == nil ? (CRXCrashBootstrap.crashCopiesDirectory ?? ownCopies) : ownCopies
        self.snapshotsDirectory = Self.snapshotsDirectory(in: folder)
        self.hangsDirectory = folder.appendingPathComponent("hangs", isDirectory: true)
        self.hangMarkerFile = folder.appendingPathComponent("anr-in-progress.json")
        self.recordsFile = folder.appendingPathComponent("crash_delivery.json")
        self.legacyHybridStoreFile = folder.appendingPathComponent("pending_crash_events.json")
    }

    // MARK: - Report copies

    /// The stored report files. A directory that does not exist yet holds none.
    func copies() -> [URL] {
        Self.files(in: copiesDirectory, withExtension: "plcrash")
    }

    func removeCopy(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Finished with a crash: its file and its delivery record both go.
    func forget(copy url: URL, crashId: String) {
        removeCopy(url)
        removeRecord(for: crashId)
    }

    private static func files(in directory: URL, withExtension pathExtension: String) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == pathExtension }
    }

    private static func writeJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    // MARK: - Fatal hangs

    /// The stored fatal hang files.
    func hangs() -> [URL] {
        Self.files(in: hangsDirectory, withExtension: "json")
    }

    /// Keeps `marker` as a hang to send, under its crash id. Returns where, or nil if it could not be written.
    func storeHang(_ marker: HangMarker) -> URL? {
        let url = hangsDirectory.appendingPathComponent("\(marker.crashId).json")
        do {
            try Self.writeJSON(marker, to: url)
            return url
        } catch {
            Log.e("[CrashDeliveryStore] Failed to store a fatal hang: \(error)")
            return nil
        }
    }

    func writeHangMarker(_ marker: HangMarker) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        do {
            try Self.writeJSON(marker, to: hangMarkerFile)
        } catch {
            Log.e("[CrashDeliveryStore] Failed to write the hang marker: \(error)")
        }
    }

    /// The marker a hang left, if any. nil too when it cannot be read yet; a corrupt one is deleted.
    func hangMarker() -> HangMarker? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let data = try? Data(contentsOf: hangMarkerFile) else { return nil }
        guard let marker = try? JSONDecoder().decode(HangMarker.self, from: data) else {
            try? FileManager.default.removeItem(at: hangMarkerFile)
            return nil
        }
        return marker
    }

    /// Whether a hang marker is still on disk: one that could not be read yet, or kept for a later
    /// launch to record.
    var hasHangMarker: Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return FileManager.default.fileExists(atPath: hangMarkerFile.path)
    }

    func clearHangMarker() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try? FileManager.default.removeItem(at: hangMarkerFile)
    }

    /// Notes that the hang `crashId` was reported by its own event, if its marker is still there.
    func markHangDelivered(crashId: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let data = try? Data(contentsOf: hangMarkerFile),
              var marker = try? JSONDecoder().decode(HangMarker.self, from: data),
              marker.crashId == crashId, !marker.liveDelivered else { return }
        marker.liveDelivered = true
        try? JSONEncoder().encode(marker).write(to: hangMarkerFile, options: .atomic)
    }

    // MARK: - Delivery records

    func record(for crashId: String) -> StoredCrashRecord? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return readLocked()?[crashId]
    }

    /// The crashes that have a delivery record; nil when the records file cannot be read yet.
    func recordedCrashIds() -> Set<String>? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return readLocked().map { Set($0.keys) }
    }

    /// Returns whether the record reached disk.
    @discardableResult
    func save(_ record: StoredCrashRecord) -> Bool {
        mutate { $0[record.crashId] = record }
    }

    /// The record of `crashId`; `.unreadable` when the records file exists but cannot be read yet,
    /// which says nothing about whether the record is there.
    func lookUpRecord(for crashId: String) -> RecordLookup {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let records = readLocked() else { return .unreadable }
        return records[crashId].map(RecordLookup.found) ?? .missing
    }

    enum RecordLookup {
        case found(StoredCrashRecord)
        case missing
        case unreadable
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
    @discardableResult
    private func mutate(_ change: (inout [String: StoredCrashRecord]) -> Void) -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard var records = readLocked() else { return false }
        change(&records)
        return writeLocked(records)
    }

    /// nil when the file exists but could not be read; empty when there is none, or it is corrupt.
    private func readLocked() -> [String: StoredCrashRecord]? {
        guard FileManager.default.fileExists(atPath: recordsFile.path) else { return [:] }
        guard let data = try? Data(contentsOf: recordsFile) else { return nil }
        return (try? JSONDecoder().decode([String: StoredCrashRecord].self, from: data)) ?? [:]
    }

    private func writeLocked(_ records: [String: StoredCrashRecord]) -> Bool {
        do {
            try Self.writeJSON(records, to: recordsFile)
            return true
        } catch {
            Log.e("[CrashDeliveryStore] Failed to write crash delivery records: \(error)")
            return false
        }
    }

    // MARK: - Migration

    /// Earlier versions kept hybrid crash events in a file of their own and re-sent them. Hybrid
    /// crashes are now sent once, live; what that file still holds is deleted, not sent.
    func deleteLegacyHybridStore() {
        try? FileManager.default.removeItem(at: legacyHybridStoreFile)
    }
}
