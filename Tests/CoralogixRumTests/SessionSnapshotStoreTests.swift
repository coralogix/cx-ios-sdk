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

    private func record(_ sessionId: String, errorCount: Int = 0) -> SessionSnapshotRecord {
        SessionSnapshotRecord(sessionId: sessionId, errorCount: errorCount, viewCount: 1, actionCount: 0, hasRecording: false)
    }

    private func files(in directory: URL) -> Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []))
    }

    private func setModified(_ date: Date, launchId: String, in directory: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date],
                                              ofItemAtPath: directory.appendingPathComponent("\(launchId).json").path)
    }

    /// A recovered crash is exported after init, and this launch's own first snapshot can be
    /// exported before it — that write must not take the crashed session's record away.
    func test_previousLaunchRecord_survivesThisLaunchsFirstSnapshot() {
        let directory = SessionSnapshotStore.temporaryDirectory()
        let store = SessionSnapshotStore.relaunched(after: crashedSessionRecord, directory: directory)
        let relaunchRecord = SessionSnapshotRecord(sessionId: "relaunch-session", errorCount: 0,
                                                   viewCount: 1, actionCount: 0, hasRecording: false)

        store.persist(relaunchRecord)

        XCTAssertEqual(store.record(for: "crashed-session"), crashedSessionRecord)
        XCTAssertEqual(store.record(for: "relaunch-session"), relaunchRecord)
        let nextLaunch = SessionSnapshotStore.temporary(directory: directory, launchId: "next-launch")
        XCTAssertEqual(nextLaunch.record(for: "relaunch-session"), relaunchRecord)
        XCTAssertEqual(nextLaunch.record(for: "crashed-session"), crashedSessionRecord,
                       "the relaunch wrote a file of its own, not over the crashed launch's")
    }

    /// A launch whose crash could not be read yet records its own session meanwhile: the launch
    /// that finally reads the crash still finds the crashed launch's record.
    func test_aLaunchsRecord_outlivesTheLaunchesAfterIt() {
        let directory = SessionSnapshotStore.temporaryDirectory()
        SessionSnapshotStore.temporary(directory: directory, launchId: "crashed").persist(record("S1", errorCount: 2))
        SessionSnapshotStore.temporary(directory: directory, launchId: "locked").persist(record("S2"))
        SessionSnapshotStore.temporary(directory: directory, launchId: "locked-again").persist(record("S3"))

        let reading = SessionSnapshotStore.temporary(directory: directory, launchId: "reading")

        XCTAssertEqual(reading.record(for: "S1")?.errorCount, 2)
        XCTAssertNotNil(reading.record(for: "S3"))
    }

    func test_rotatedOutSessionsRecord_survivesTheNewSessionsFirstSnapshot() {
        let store = SessionSnapshotStore.temporary()
        let rotatedOutRecord = SessionSnapshotRecord(sessionId: "rotated-out-session", errorCount: 1,
                                                     viewCount: 2, actionCount: 3, hasRecording: false)
        store.persist(rotatedOutRecord)

        store.persist(record("new-session"))

        XCTAssertEqual(store.record(for: "rotated-out-session"), rotatedOutRecord)
    }

    func test_adjustErrorCount_neverGoesBelowZero() {
        let store = SessionSnapshotStore.relaunched(after: record("crashed-session"))

        XCTAssertEqual(store.adjustErrorCount(of: "crashed-session", by: -1)?.errorCount, 0)
    }

    func test_adjustErrorCount_ofAnEarlierLaunch_changesItInMemoryOnly() {
        let directory = SessionSnapshotStore.temporaryDirectory()
        let store = SessionSnapshotStore.relaunched(after: record("earlier", errorCount: 1), directory: directory)

        XCTAssertEqual(store.adjustErrorCount(of: "earlier", by: 1)?.errorCount, 2)
        XCTAssertEqual(store.adjustErrorCount(of: "earlier", by: 1)?.errorCount, 3, "counts on from the last error")
        XCTAssertEqual(SessionSnapshotStore.temporary(directory: directory, launchId: "next").record(for: "earlier")?.errorCount, 1,
                       "the file is the earlier launch's own")
    }

    // MARK: - Pruning

    func test_aRecordOlderThanACrashMayBeSent_isDeletedAtInit() throws {
        let directory = SessionSnapshotStore.temporaryDirectory()
        let now = Date()
        SessionSnapshotStore.temporary(directory: directory, launchId: "expired").persist(record("old"))
        SessionSnapshotStore.temporary(directory: directory, launchId: "recent").persist(record("new"))
        try setModified(now.addingTimeInterval(-SessionSnapshotStore.maxAge - 60), launchId: "expired", in: directory)
        try setModified(now.addingTimeInterval(-SessionSnapshotStore.maxAge + 60), launchId: "recent", in: directory)

        let store = SessionSnapshotStore.temporary(directory: directory, launchId: "current", now: now)

        XCTAssertNil(store.record(for: "old"))
        XCTAssertNotNil(store.record(for: "new"))
        XCTAssertEqual(files(in: directory), ["recent.json"])
    }

    func test_onlyTheNewestLaunchesRecords_areKept() throws {
        let directory = SessionSnapshotStore.temporaryDirectory()
        let now = Date()
        let launches = SessionSnapshotStore.maxEarlierLaunches + 2
        for index in 0..<launches {
            SessionSnapshotStore.temporary(directory: directory, launchId: "launch-\(index)").persist(record("S\(index)"))
            try setModified(now.addingTimeInterval(TimeInterval(index - launches)), launchId: "launch-\(index)", in: directory)
        }

        let store = SessionSnapshotStore.temporary(directory: directory, launchId: "current", now: now)

        XCTAssertNil(store.record(for: "S0"))
        XCTAssertNil(store.record(for: "S1"))
        XCTAssertNotNil(store.record(for: "S2"))
        XCTAssertNotNil(store.record(for: "S\(launches - 1)"))
        XCTAssertEqual(files(in: directory).count, SessionSnapshotStore.maxEarlierLaunches)
    }

    func test_aRecordThatCannotBeReadYet_isKept_andACorruptOneDeleted() throws {
        let directory = SessionSnapshotStore.temporaryDirectory()
        SessionSnapshotStore.temporary(directory: directory, launchId: "locked").persist(record("S1"))
        let locked = directory.appendingPathComponent("locked.json")
        try Data("not a record".utf8).write(to: directory.appendingPathComponent("corrupt.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        let store = SessionSnapshotStore.temporary(directory: directory, launchId: "current")

        XCTAssertNil(store.record(for: "S1"))
        XCTAssertEqual(files(in: directory), ["locked.json"])
    }

    func test_discardEarlierLaunch_deletesOnlyThatLaunchsFile_andKeepsItsRecordInMemory() {
        let directory = SessionSnapshotStore.temporaryDirectory()
        SessionSnapshotStore.temporary(directory: directory, launchId: "crashed").persist(record("S1"))
        SessionSnapshotStore.temporary(directory: directory, launchId: "other").persist(record("S2"))
        let store = SessionSnapshotStore.temporary(directory: directory, launchId: "current")
        store.persist(record("live"))

        store.discardEarlierLaunch(of: "S1")

        XCTAssertEqual(files(in: directory), ["other.json", "current.json"])
        XCTAssertNotNil(store.record(for: "S1"), "spans of the session can still be exported")
    }

    func test_discardEarlierLaunches_keepsOnlyTheNamedLaunchsFile() {
        let directory = SessionSnapshotStore.temporaryDirectory()
        SessionSnapshotStore.temporary(directory: directory, launchId: "crashed").persist(record("S1"))
        SessionSnapshotStore.temporary(directory: directory, launchId: "other").persist(record("S2"))
        let store = SessionSnapshotStore.temporary(directory: directory, launchId: "current")
        store.persist(record("live"))

        SessionSnapshotStore.discardEarlierLaunches(in: directory, keeping: store.launchId)

        XCTAssertEqual(files(in: directory), ["current.json"])
        XCTAssertNotNil(store.record(for: "S2"))
        XCTAssertEqual(SessionSnapshotStore.temporary(directory: directory, launchId: "next").record(for: "live"),
                       record("live"))
    }

    /// The SDK initialized again in the same process writes over its launch's file.
    func test_aSecondStoreOfTheSameLaunch_writesOverItsFile() {
        let directory = SessionSnapshotStore.temporaryDirectory()
        SessionSnapshotStore.temporary(directory: directory, launchId: "process").persist(record("first-init"))
        let reinitialized = SessionSnapshotStore.temporary(directory: directory, launchId: "process")

        reinitialized.persist(record("second-init"))

        XCTAssertNotNil(reinitialized.record(for: "first-init"), "read at init, like any earlier record")
        XCTAssertEqual(files(in: directory), ["process.json"])
    }

    // MARK: - Upgrade from the keychain record

    func test_theKeychainRecordOfAnEarlierVersion_isMovedIntoAFile_andReadByLaterLaunches() throws {
        let directory = SessionSnapshotStore.temporaryDirectory()
        let keychain = MockKeyChain()
        keychain.writeStringToKeychain(service: Keys.service.rawValue, key: Keys.keySessionSnapshot.rawValue,
                                       value: try XCTUnwrap(crashedSessionRecord.json))

        let upgraded = SessionSnapshotStore.temporary(directory: directory, launchId: "upgraded", keychain: keychain)
        upgraded.persist(record("upgraded-session"))

        XCTAssertEqual(upgraded.record(for: "crashed-session"), crashedSessionRecord)
        XCTAssertNil(keychain.readStringFromKeychain(service: Keys.service.rawValue, key: Keys.keySessionSnapshot.rawValue))
        // The crash was not readable on the upgraded launch: the one after still has its record.
        let later = SessionSnapshotStore.temporary(directory: directory, launchId: "later", keychain: keychain)
        XCTAssertEqual(later.record(for: "crashed-session"), crashedSessionRecord)
    }

    func test_theKeychainRecord_staysWhenItsFileCannotBeWritten() throws {
        let blocker = SessionSnapshotStore.temporaryDirectory()
        // A file where the directory should be: nothing can be written under it.
        try Data().write(to: blocker)
        let keychain = MockKeyChain()
        keychain.writeStringToKeychain(service: Keys.service.rawValue, key: Keys.keySessionSnapshot.rawValue,
                                       value: try XCTUnwrap(crashedSessionRecord.json))

        let store = SessionSnapshotStore.temporary(directory: blocker, keychain: keychain)

        XCTAssertEqual(store.record(for: "crashed-session"), crashedSessionRecord)
        XCTAssertNotNil(keychain.readStringFromKeychain(service: Keys.service.rawValue, key: Keys.keySessionSnapshot.rawValue))
    }
}
