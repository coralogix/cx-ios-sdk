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
/// a crash recovered on the next launch, a span restored to the previous session by pid, or a
/// span exported after a rotation. Those events must not read or bump the live session's
/// counters, which describe a different session.
///
/// `LiveSessionRecorder` writes the live session's record to one keychain slot whenever its
/// counters, view or versions change. The slot is read once, at init: by the time a recovered
/// crash is exported, this launch's own first record may already have overwritten it.
final class SessionSnapshotStore {
    private typealias Slot = ReferenceWritableKeyPath<SessionSnapshotStore, SessionSnapshotRecord?>

    private let keychain: KeyChainProtocol
    private let lock = NSLock()
    /// What the keychain slot holds: the latest record this launch persisted.
    private var latestRecord: SessionSnapshotRecord?
    /// The record `latestRecord` replaced when a new session was first recorded. Spans of
    /// the rotated-out session can still be exported after that, in the same batch or later.
    private var previousRecord: SessionSnapshotRecord?
    /// The previous launch's last record — the crashed session's, when that launch crashed.
    private var lastLaunchRecord: SessionSnapshotRecord?

    init(keychain: KeyChainProtocol = KeychainManager()) {
        self.keychain = keychain
        self.lastLaunchRecord = keychain.readStringFromKeychain(service: Keys.service.rawValue,
                                                                key: Keys.keySessionSnapshot.rawValue)
            .flatMap(SessionSnapshotRecord.init(json:))
    }

    /// The recorder writes on every counter and view change, so an unchanged record skips the
    /// keychain write.
    func persist(_ record: SessionSnapshotRecord) {
        lock.lock()
        defer { lock.unlock() }
        persistLocked(record)
    }

    private func persistLocked(_ record: SessionSnapshotRecord) {
        guard record != latestRecord else { return }
        if let latestRecord, latestRecord.sessionId != record.sessionId {
            previousRecord = latestRecord
        }
        latestRecord = record
        writeLocked(record)
    }

    func record(for sessionId: String) -> SessionSnapshotRecord? {
        lock.lock()
        defer { lock.unlock() }
        return slotLocked(for: sessionId).flatMap { self[keyPath: $0] }
    }

    /// Moves the error count recorded for `sessionId` by `delta`, never below zero, so a second
    /// error in the same retired session counts on from the first. Returns the updated record,
    /// or nil when there is no record of the session. The keychain record is written through, so
    /// a crash before the recorder's next write still recovers the corrected count; the other records
    /// change in memory only, since the slot is not theirs.
    func adjustErrorCount(of sessionId: String, by delta: Int) -> SessionSnapshotRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = slotLocked(for: sessionId), var record = self[keyPath: slot] else { return nil }
        record.errorCount = max(0, record.errorCount + delta)
        self[keyPath: slot] = record
        if slot == \SessionSnapshotStore.latestRecord {
            writeLocked(record)
        }
        return record
    }

    private func slotLocked(for sessionId: String) -> Slot? {
        let slots: [Slot] = [\.latestRecord, \.previousRecord, \.lastLaunchRecord]
        return slots.first { self[keyPath: $0]?.sessionId == sessionId }
    }

    private func writeLocked(_ record: SessionSnapshotRecord) {
        guard let json = record.json else {
            Log.e("[SessionSnapshotStore] Failed to encode the session snapshot record")
            return
        }
        keychain.writeStringToKeychain(service: Keys.service.rawValue,
                                       key: Keys.keySessionSnapshot.rawValue,
                                       value: json)
    }
}
