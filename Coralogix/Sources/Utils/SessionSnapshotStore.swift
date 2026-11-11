//
//  SessionSnapshotStore.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// One session as a crash in it must report it: its counters, the view it was on, and the app
/// and OS it ran under. The context fields are optional so records written by earlier versions,
/// which had counters only, still decode.
struct SessionSnapshotRecord: Codable, Equatable {
    let sessionId: String
    var errorCount: Int
    let viewCount: Int
    let actionCount: Int
    let hasRecording: Bool
    var viewName: String? = nil
    var viewNumber: Int? = nil
    var appName: String? = nil
    var appVersion: String? = nil
    var osVersion: String? = nil
}

extension SessionSnapshotRecord {
    /// A session the SDK adopted but had not recorded yet: nothing counted, no view.
    static func empty(sessionId: String) -> SessionSnapshotRecord {
        SessionSnapshotRecord(sessionId: sessionId, errorCount: 0, viewCount: 0, actionCount: 0, hasRecording: false)
    }

    func snapshotContext() -> SnapshotContext {
        SnapshotContext(timestamp: Date().timeIntervalSince1970,
                        errorCount: errorCount,
                        viewCount: viewCount,
                        actionCount: actionCount,
                        hasRecording: hasRecording)
    }
}

extension SessionSnapshotRecord {
    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let record = try? JSONDecoder().decode(SessionSnapshotRecord.self, from: data) else { return nil }
        self = record
    }

    var json: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Counters of sessions that are no longer live, for events still reported under one of them —
/// a crash recovered on a later launch, a span restored to the previous session by pid, or a
/// span exported after a rotation. Those events must not read or bump the live session's
/// counters, which describe a different session.
///
/// `LiveSessionRecorder` writes the live session's record to this launch's own file whenever its
/// counters, view or versions change. One file per launch, so a launch whose crash could not be
/// read yet (the device was still locked) keeps its record however many launches pass before the
/// crash is read. A crash finds its launch's file by the session its report names: every launch
/// starts sessions of its own, so a session belongs to exactly one launch.
///
/// Earlier launches' files are read once, at init: by the time a recovered crash is exported, they
/// may already be deleted (`discardEarlierLaunches(in:keeping:)`), since the crash's own delivery
/// record holds what it needs. Files older than a crash may be sent, or beyond the newest
/// `maxEarlierLaunches`, are deleted at init.
final class SessionSnapshotStore {
    private typealias Slot = ReferenceWritableKeyPath<SessionSnapshotStore, SessionSnapshotRecord?>

    /// Earlier launches whose records are kept; a crash is read on the first launch after the
    /// first unlock, so a crash waiting longer than this many launches is not expected.
    static let maxEarlierLaunches = 10
    /// The age past which a crash is no longer sent, so nothing needs the record of its launch.
    static let maxAge = CrashDeliveryScheduler.maxAge
    /// Names this process's file. Not the session id minted at image load: the SDK can be
    /// initialized again in the same process, and that instance must write over this launch's
    /// file, not leave a second one.
    static let processLaunchId = UUID().uuidString.lowercased()
    /// The file a 2.22 keychain record is moved into; that version kept one record in all.
    static let legacyLaunchId = "keychain"
    private static let fileExtension = "json"

    static var defaultDirectory: URL {
        CrashDeliveryStore.snapshotsDirectory(in: CrashDeliveryStore.defaultFolder)
    }

    private let directory: URL
    let launchId: String
    private let lock = NSLock()
    /// What this launch's file holds: the latest record this launch persisted.
    private var latestRecord: SessionSnapshotRecord?
    /// The record `latestRecord` replaced when a new session was first recorded. Spans of
    /// the rotated-out session can still be exported after that, in the same batch or later.
    private var previousRecord: SessionSnapshotRecord?
    /// The last record of every earlier launch on disk at init, by launch id — the crashed
    /// session's among them, when one of those launches crashed.
    private var earlierRecords: [String: SessionSnapshotRecord]

    init(keychain: KeyChainProtocol = KeychainManager(),
         directory: URL = SessionSnapshotStore.defaultDirectory,
         launchId: String = SessionSnapshotStore.processLaunchId,
         now: Date = Date()) {
        self.directory = directory
        self.launchId = launchId
        self.earlierRecords = Self.readEarlierLaunches(in: directory, now: now)
        moveLegacyRecord(from: keychain)
    }

    /// The recorder writes on every counter and view change, so an unchanged record skips the
    /// write.
    func persist(_ record: SessionSnapshotRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard record != latestRecord else { return }
        if let latestRecord, latestRecord.sessionId != record.sessionId {
            previousRecord = latestRecord
        }
        latestRecord = record
        write(record, launchId: launchId)
    }

    func record(for sessionId: String) -> SessionSnapshotRecord? {
        lock.lock()
        defer { lock.unlock() }
        return slotLocked(for: sessionId).flatMap { self[keyPath: $0] }
    }

    /// Moves the error count recorded for `sessionId` by `delta`, never below zero, so a second
    /// error in the same retired session counts on from the first. Returns the updated record,
    /// or nil when there is no record of the session. This launch's record is written through, so
    /// a crash before the recorder's next write still recovers the corrected count; the other
    /// records change in memory only, since the file is not theirs.
    func adjustErrorCount(of sessionId: String, by delta: Int) -> SessionSnapshotRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = slotLocked(for: sessionId), var record = self[keyPath: slot] else { return nil }
        record.errorCount = max(0, record.errorCount + delta)
        self[keyPath: slot] = record
        if slot == \SessionSnapshotStore.latestRecord {
            write(record, launchId: launchId)
        }
        return record
    }

    /// Deletes the file of the earlier launch `sessionId` belongs to, once its crash has a
    /// delivery record of its own. Kept in memory: spans of that session can still be exported.
    func discardEarlierLaunch(of sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        for (id, record) in earlierRecords where record.sessionId == sessionId && id != launchId {
            removeFile(of: id)
        }
    }

    /// Deletes every earlier launch's file in `directory`, once recovery has read every crash and
    /// hang those launches left; `launchId`'s is kept. A store keeps the records in memory: spans
    /// of those sessions can still be exported.
    static func discardEarlierLaunches(in directory: URL, keeping launchId: String) {
        for file in launchFiles(in: directory) where file.id != launchId {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    private func slotLocked(for sessionId: String) -> Slot? {
        let slots: [Slot] = [\.latestRecord, \.previousRecord] + earlierRecords.keys.map { \.earlierRecords[$0] }
        return slots.first { self[keyPath: $0]?.sessionId == sessionId }
    }

    /// Moves the record 2.22 kept in the keychain into a file, so a crash it left is read with
    /// it on whichever launch first can. The keychain item goes only once the file is written.
    private func moveLegacyRecord(from keychain: KeyChainProtocol) {
        let service = Keys.service.rawValue, key = Keys.keySessionSnapshot.rawValue
        guard let record = keychain.readStringFromKeychain(service: service, key: key)
            .flatMap(SessionSnapshotRecord.init(json:)) else { return }
        lock.lock()
        defer { lock.unlock() }
        earlierRecords[Self.legacyLaunchId] = record
        if write(record, launchId: Self.legacyLaunchId) {
            keychain.deleteFromKeychain(service: service, key: key)
        }
    }

    // MARK: - Files

    private func fileURL(of launchId: String) -> URL {
        directory.appendingPathComponent(launchId).appendingPathExtension(Self.fileExtension)
    }

    /// Readable from the first unlock on, which is when recovery can read the crash too, whatever
    /// default protection the host app sets.
    @discardableResult
    private func write(_ record: SessionSnapshotRecord, launchId: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: fileURL(of: launchId),
                                                   options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            Log.e("[SessionSnapshotStore] Failed to write the session snapshot record: \(error)")
            return false
        }
    }

    private func removeFile(of launchId: String) {
        try? FileManager.default.removeItem(at: fileURL(of: launchId))
    }

    private static func launchFiles(in directory: URL) -> [(id: String, url: URL, modified: Date)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == fileExtension }.map { url in
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (url.deletingPathExtension().lastPathComponent, url, modified ?? .distantPast)
        }
    }

    /// Every launch's record still worth keeping, this process's own included for an SDK
    /// initialized again; the rest are deleted. A file that cannot be read yet is left for a
    /// later launch, and one that is corrupt is deleted.
    private static func readEarlierLaunches(in directory: URL, now: Date) -> [String: SessionSnapshotRecord] {
        let newestFirst = launchFiles(in: directory).sorted { $0.modified > $1.modified }
        var records: [String: SessionSnapshotRecord] = [:]
        for (index, file) in newestFirst.enumerated() {
            guard index < maxEarlierLaunches, now.timeIntervalSince(file.modified) <= maxAge else {
                try? FileManager.default.removeItem(at: file.url)
                continue
            }
            guard let data = try? Data(contentsOf: file.url) else { continue }
            guard let record = try? JSONDecoder().decode(SessionSnapshotRecord.self, from: data) else {
                try? FileManager.default.removeItem(at: file.url)
                continue
            }
            records[file.id] = record
        }
        return records
    }
}
