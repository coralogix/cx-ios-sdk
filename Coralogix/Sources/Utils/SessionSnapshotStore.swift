//
//  SessionSnapshotStore.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// The counters one session's snapshot carried, tagged with that session's id.
struct SessionSnapshotRecord: Codable, Equatable {
    let sessionId: String
    var errorCount: Int
    let viewCount: Int
    let actionCount: Int
    let hasRecording: Bool
}

extension SessionSnapshotRecord {
    init(sessionId: String, snapshot: SnapshotContext) {
        self.init(sessionId: sessionId,
                  errorCount: snapshot.errorCount,
                  viewCount: snapshot.viewCount,
                  actionCount: snapshot.actionCount,
                  hasRecording: snapshot.hasRecording)
    }

    func snapshotContext() -> SnapshotContext {
        SnapshotContext(timestamp: Date().timeIntervalSince1970,
                        errorCount: errorCount,
                        viewCount: viewCount,
                        actionCount: actionCount,
                        hasRecording: hasRecording)
    }
}

private extension SessionSnapshotRecord {
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
/// The live session's counters are persisted to one keychain slot each time it emits a snapshot.
/// The slot is read once, at init: by the time a recovered crash is exported, this launch's own
/// first snapshot may already have overwritten it.
final class SessionSnapshotStore {
    private let keychain: KeyChainProtocol
    private let lock = NSLock()
    /// The previous launch's last record — the crashed session's, when that launch crashed.
    private var lastLaunchRecord: SessionSnapshotRecord?
    /// The latest record this launch persisted, which still describes a session this launch
    /// rotated out of until the new session emits its first snapshot.
    private var latestRecord: SessionSnapshotRecord?

    init(keychain: KeyChainProtocol = KeychainManager()) {
        self.keychain = keychain
        self.lastLaunchRecord = keychain.readStringFromKeychain(service: Keys.service.rawValue,
                                                                key: Keys.keySessionSnapshot.rawValue)
            .flatMap(SessionSnapshotRecord.init(json:))
    }

    /// Snapshots fire on every error and navigation, so an unchanged record skips the keychain write.
    func persist(_ record: SessionSnapshotRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard record != latestRecord else { return }
        latestRecord = record
        guard let json = record.json else {
            Log.e("[SessionSnapshotStore] Failed to encode the session snapshot record")
            return
        }
        keychain.writeStringToKeychain(service: Keys.service.rawValue,
                                       key: Keys.keySessionSnapshot.rawValue,
                                       value: json)
    }

    func record(for sessionId: String) -> SessionSnapshotRecord? {
        lock.lock()
        defer { lock.unlock() }
        return recordLocked(for: sessionId)
    }

    /// Moves the error count recorded for `sessionId` by `delta`, never below zero, so a second
    /// error in the same retired session counts on from the first. Returns the updated record,
    /// or nil when there is no record of the session. Memory only: the keychain slot belongs to
    /// the live session.
    func adjustErrorCount(of sessionId: String, by delta: Int) -> SessionSnapshotRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard var record = recordLocked(for: sessionId) else { return nil }
        record.errorCount = max(0, record.errorCount + delta)
        if lastLaunchRecord?.sessionId == sessionId {
            lastLaunchRecord = record
        } else {
            latestRecord = record
        }
        return record
    }

    private func recordLocked(for sessionId: String) -> SessionSnapshotRecord? {
        [lastLaunchRecord, latestRecord].compactMap { $0 }.first { $0.sessionId == sessionId }
    }
}
