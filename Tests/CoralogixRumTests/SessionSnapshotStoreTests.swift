//
//  SessionSnapshotStoreTests.swift
//  Coralogix
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class SessionSnapshotStoreTests: XCTestCase {

    private let crashedSessionRecord = SessionSnapshotRecord(sessionId: "crashed-session",
                                                             errorCount: 2,
                                                             viewCount: 3,
                                                             actionCount: 4,
                                                             hasRecording: true)

    /// A recovered crash is exported after init, and this launch's own first snapshot can be
    /// exported before it — that write must not take the crashed session's record away.
    func test_previousLaunchRecord_survivesThisLaunchsFirstSnapshot() {
        let keychain = MockKeyChain()
        let store = SessionSnapshotStore.relaunched(after: crashedSessionRecord, keychain: keychain)
        let relaunchRecord = SessionSnapshotRecord(sessionId: "relaunch-session", errorCount: 0,
                                                   viewCount: 1, actionCount: 0, hasRecording: false)

        store.persist(relaunchRecord)

        XCTAssertEqual(store.record(for: "crashed-session"), crashedSessionRecord)
        XCTAssertEqual(store.record(for: "relaunch-session"), relaunchRecord)
        XCTAssertEqual(SessionSnapshotStore(keychain: keychain).record(for: "relaunch-session"), relaunchRecord,
                       "The keychain slot now holds this launch's record, for the launch after it")
    }

    func test_rotatedOutSessionsRecord_survivesTheNewSessionsFirstSnapshot() {
        let store = SessionSnapshotStore(keychain: MockKeyChain())
        let rotatedOutRecord = SessionSnapshotRecord(sessionId: "rotated-out-session", errorCount: 1,
                                                     viewCount: 2, actionCount: 3, hasRecording: false)
        store.persist(rotatedOutRecord)

        store.persist(SessionSnapshotRecord(sessionId: "new-session", errorCount: 0,
                                            viewCount: 1, actionCount: 0, hasRecording: false))

        XCTAssertEqual(store.record(for: "rotated-out-session"), rotatedOutRecord)
    }

    func test_adjustErrorCount_neverGoesBelowZero() {
        let store = SessionSnapshotStore.relaunched(after: SessionSnapshotRecord(sessionId: "crashed-session",
                                                                                 errorCount: 0,
                                                                                 viewCount: 1,
                                                                                 actionCount: 1,
                                                                                 hasRecording: false))

        XCTAssertEqual(store.adjustErrorCount(of: "crashed-session", by: -1)?.errorCount, 0)
    }
}
