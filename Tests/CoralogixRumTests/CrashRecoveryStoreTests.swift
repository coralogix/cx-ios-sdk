//
//  CrashRecoveryStoreTests.swift
//
//  Each crash report is kept as the SDK's own copy, with a delivery record written the first time
//  a launch reads it. A crash is sent as that record describes it on every launch until it is
//  delivered, so a crash recovered launches later still reports the session, view, counters and
//  versions it happened under. A crash whose session left no record is dropped.
//

import XCTest
import CrashReporter
import CoralogixInternal
#if canImport(CoralogixBootstrap)
import CoralogixBootstrap
#endif

@testable import Coralogix

// MARK: - Fixtures

/// Records every request and answers each one with `result`.
private final class SwitchableUploader: SpanUploading {
    var result = SpanUploadResult.delivered
    private let lock = NSLock()
    private var _events: [[String: Any]] = []
    var events: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return _events }

    static let serverError = SpanUploadResult(disposition: .retryable, httpStatus: 503, retryAfter: nil,
                                              countsAsFailedUpload: true)

    func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
        lock.lock(); defer { lock.unlock() }
        _events.append(contentsOf: spans)
        return result
    }

    var crashes: [[String: Any]] {
        events.compactMap { event in
            let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
            let errorContext = cxRum?[Keys.errorContext.rawValue] as? [String: Any]
            return errorContext?[Keys.isCrash.rawValue] as? Bool == true ? cxRum : nil
        }
    }
}

private func crashContext(sessionId: String?) -> Data? {
    sessionId.map {
        Data(#"{"v":1,"session":{"session_id":"\#($0)","session_creation_time":1700000000000,"is_session_sampled_in":true}}"#.utf8)
    }
}

/// A real report naming `sessionId` in its crash context, the way a crash in that session leaves one.
private func liveReportData(sessionId: String?) throws -> Data {
    let reporter = try XCTUnwrap(PLCrashReporter(configuration: PLCrashReporterConfig(signalHandlerType: .BSD,
                                                                                     symbolicationStrategy: [])))
    reporter.customData = crashContext(sessionId: sessionId)
    return try reporter.generateLiveReportAndReturnError()
}

/// Leaves a crash in `store` as the load-time copy does, and returns it as recovery will read it.
@discardableResult
private func leaveCrash(in store: CrashDeliveryStore, sessionId: String?) throws -> MappedCrash {
    let data = try liveReportData(sessionId: sessionId)
    let crash = CrashReportMapper.map(PLCrashReportReader(report: try PLCrashReport(data: data)))
    try FileManager.default.createDirectory(at: store.copiesDirectory, withIntermediateDirectories: true)
    try data.write(to: store.copiesDirectory.appendingPathComponent("\(crash.crashId).plcrash"))
    return crash
}

private func sessionRecord(of sessionId: String, view: String? = "Checkout", appVersion: String = "1.0",
                    errorCount: Int = 2) -> SessionSnapshotRecord {
    SessionSnapshotRecord(sessionId: sessionId, errorCount: errorCount, viewCount: 1, actionCount: 4,
                          hasRecording: false, viewName: view, viewNumber: view == nil ? nil : 0,
                          appName: "TestApp", appVersion: appVersion, osVersion: "17.0")
}

// MARK: - Recovery across launches

final class CrashRecoveryAcrossLaunchesTests: XCTestCase {

    private var launches: [CoralogixRum] = []

    override func tearDownWithError() throws {
        launches.forEach { $0.shutdown() }
        launches = []
        try super.tearDownWithError()
    }

    /// A launch whose snapshot store holds `lastSession` from the launch before, recovering from
    /// `store`, sending through `uploader`.
    private func launch(store: CrashDeliveryStore, lastSession: SessionSnapshotRecord?,
                        uploader: SwitchableUploader, version: String = "9.9") throws -> CoralogixRum {
        let manager = SessionManager(snapshotStore: .relaunched(after: lastSession))
        manager.lastLaunchSession = nil
        var options = makeSamplingOptions(sampleRate: 100, exclude: [])
        options.version = version
        let sdk = CoralogixRum(options: options, sessionManager: manager)
        launches.append(sdk)
        sdk.crashDeliveryStore = store
        try XCTUnwrap(sdk.coralogixExporter).spanUploader = uploader

        sdk.recoverPendingCrashes()
        let recovered = expectation(description: "recovery complete")
        sdk.completeCrashRecovery { recovered.fulfill() }
        wait(for: [recovered], timeout: 10)
        return sdk
    }

    private func value(_ crash: [String: Any], _ context: Keys, _ key: Keys) -> Any? {
        (crash[context.rawValue] as? [String: Any])?[key.rawValue]
    }

    /// Launch 1 crashes in S1; launch 2 cannot deliver it; launch 3 runs with S1's snapshot long
    /// gone from the keychain and still reports S1, its view, counters and app version.
    func test_aCrashDeliveredTwoLaunchesLater_stillReportsItsOwnSession() throws {
        let store = CrashDeliveryStore.temporary()
        let crash = try leaveCrash(in: store, sessionId: "S1")

        let failing = SwitchableUploader()
        failing.result = SwitchableUploader.serverError
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: failing)
        XCTAssertEqual(failing.crashes.count, 1, "launch 2 tried")
        XCTAssertEqual(store.copies().count, 1, "an undelivered crash is kept")
        XCTAssertNotNil(store.record(for: crash.crashId))

        let delivering = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S2", view: "Elsewhere", appVersion: "2.0"), uploader: delivering)

        let sent = try XCTUnwrap(delivering.crashes.first)
        XCTAssertEqual(value(sent, .sessionContext, .sessionId) as? String, "S1")
        XCTAssertEqual(value(sent, .viewContext, .view) as? String, "Checkout")
        XCTAssertEqual(value(sent, .versionMetaData, .appVersion) as? String, "1.0")
        XCTAssertTrue(store.copies().isEmpty, "a delivered crash's copy is deleted")
        XCTAssertNil(store.record(for: crash.crashId))
    }

    /// PLCrashReporter's single slot would have kept only the last of these.
    func test_threeUndeliveredCrashes_areAllSent_newestFirst() throws {
        let store = CrashDeliveryStore.temporary()
        var crashes: [MappedCrash] = []
        for session in ["S1", "S2", "S3"] {
            let crash = try leaveCrash(in: store, sessionId: session)
            store.save(.fixture(crashId: crash.crashId, sessionId: session, counters: sessionRecord(of: session)))
            crashes.append(crash)
        }

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: nil, uploader: uploader)

        let sessions = uploader.crashes.map { value($0, .sessionContext, .sessionId) as? String }
        XCTAssertEqual(sessions, ["S3", "S2", "S1"])
        XCTAssertTrue(store.copies().isEmpty)
    }

    func test_aCrashSentOnEveryLaunch_reportsTheSameErrorCount_andChangesNoStore() throws {
        let store = CrashDeliveryStore.temporary()
        let crash = try leaveCrash(in: store, sessionId: "S1")
        let failing = SwitchableUploader()
        failing.result = SwitchableUploader.serverError

        for _ in 0..<3 {
            try launch(store: store, lastSession: sessionRecord(of: "S1", errorCount: 2), uploader: failing)
        }

        let counts = failing.crashes.map { value($0, .snapshotContext, .errorCount) as? Int }
        XCTAssertEqual(counts, [3, 3, 3], "the session's two errors plus this crash, every time")
        XCTAssertEqual(store.record(for: crash.crashId)?.counters.errorCount, 2, "never written back")
    }

    func test_aCrashWhoseSessionLeftNoRecord_isDropped_andItsCopyDeleted() throws {
        let store = CrashDeliveryStore.temporary()
        try leaveCrash(in: store, sessionId: "never-adopted")

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "some-other-session"), uploader: uploader)

        XCTAssertTrue(uploader.crashes.isEmpty)
        XCTAssertTrue(store.copies().isEmpty)
    }

    func test_aCorruptCopy_isDeleted_andAnUnreadableOneKept() throws {
        let store = CrashDeliveryStore.temporary()
        try FileManager.default.createDirectory(at: store.copiesDirectory, withIntermediateDirectories: true)
        let corrupt = store.copiesDirectory.appendingPathComponent("corrupt.plcrash")
        try Data("not a report".utf8).write(to: corrupt)
        let locked = store.copiesDirectory.appendingPathComponent("locked.plcrash")
        try liveReportData(sessionId: "S1").write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        XCTAssertEqual(CoralogixRum.readCopy(locked).isNotReadableYet, true)
        try launch(store: store, lastSession: nil, uploader: SwitchableUploader())

        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locked.path), "a file that cannot be read yet is not corrupt")
    }

    func test_aHybridCrash_isSentOnce_andNothingIsKeptOnDisk() throws {
        let store = CrashDeliveryStore.temporary()
        let failing = SwitchableUploader()
        failing.result = SwitchableUploader.serverError
        let sdk = try launch(store: store, lastSession: nil, uploader: failing)

        sdk.reportError(message: "TypeError: undefined is not a function", stackTrace: [], errorType: "TypeError",
                        isCrash: true)
        let flushed = expectation(description: "flushed")
        sdk.flush { flushed.fulfill() }
        wait(for: [flushed], timeout: 10)
        XCTAssertEqual(failing.crashes.count, 1)

        let relaunch = SwitchableUploader()
        try launch(store: store, lastSession: nil, uploader: relaunch)
        XCTAssertTrue(relaunch.crashes.isEmpty, "a hybrid crash whose upload failed is not sent again")
        XCTAssertTrue(store.copies().isEmpty)
    }

    func test_theEarlierHybridCrashFile_isDeleted_withoutSendingIt() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")
        let folder = base.appendingPathComponent("CoralogixRum", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = folder.appendingPathComponent("pending_crash_events.json")
        try Data(#"[{"error_message":"old hybrid crash","store_event_id":"x"}]"#.utf8).write(to: legacy)

        let uploader = SwitchableUploader()
        try launch(store: CrashDeliveryStore(directory: base), lastSession: nil, uploader: uploader)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(uploader.crashes.isEmpty)
    }
}

private extension CoralogixRum.CopyReadResult {
    var isNotReadableYet: Bool {
        if case .notReadableYet = self { return true }
        return false
    }
}

// MARK: - The store and the copy

final class CrashDeliveryStoreTests: XCTestCase {

    func test_onlyTheNewestTenCopies_areKept() throws {
        let store = CrashDeliveryStore.temporary()
        try FileManager.default.createDirectory(at: store.copiesDirectory, withIntermediateDirectories: true)
        let crashes = (0..<11).map { index -> (URL, MappedCrash) in
            let url = store.copiesDirectory.appendingPathComponent("\(index).plcrash")
            return (url, makeCrash(id: "c\(index)", time: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))))
        }

        let (kept, dropped) = CoralogixRum.newest(crashes.shuffled(), limit: CrashDeliveryStore.maxPerKind)

        XCTAssertEqual(kept.map(\.crash.crashId), (1...10).reversed().map { "c\($0)" })
        XCTAssertEqual(dropped.map(\.crash.crashId), ["c0"])
    }

    func test_aRecordsFileThatCannotBeRead_isNotOverwritten() throws {
        let store = CrashDeliveryStore.temporary()
        store.save(.fixture(crashId: "first"))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: store.copiesDirectory.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent == "crash_delivery.json" })
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        XCTAssertNil(try? Data(contentsOf: file), "precondition: the file cannot be read")

        store.save(.fixture(crashId: "second"))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertNotNil(store.record(for: "first"), "an unreadable file is not corrupt; it must survive")
        XCTAssertNil(store.record(for: "second"), "nothing is written while the file cannot be read")
    }

    func test_aCorruptRecordsFile_isReplaced() throws {
        let store = CrashDeliveryStore.temporary()
        store.save(.fixture(crashId: "first"))
        let file = store.copiesDirectory.deletingLastPathComponent().appendingPathComponent("crash_delivery.json")
        try Data("garbage".utf8).write(to: file)

        store.save(.fixture(crashId: "second"))

        XCTAssertNotNil(store.record(for: "second"))
    }

    // MARK: Moving PLCrashReporter's pending report

    private func reporterWithPendingReport() throws -> PLCrashReporter {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("plcr-\(UUID().uuidString)").path
        let reporter = try XCTUnwrap(PLCrashReporter(configuration: PLCrashReporterConfig(
            signalHandlerType: .BSD, symbolicationStrategy: [], basePath: base)))
        let path = try XCTUnwrap(reporter.crashReportPath())
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try liveReportData(sessionId: "S1").write(to: URL(fileURLWithPath: path))
        XCTAssertTrue(reporter.hasPendingCrashReport())
        return reporter
    }

    func test_thePendingReport_isMovedIntoACopyNamedByItsUUID() throws {
        let reporter = try reporterWithPendingReport()
        let store = CrashDeliveryStore.temporary()

        XCTAssertTrue(CRXCrashBootstrap.movePendingReport(of: reporter, toDirectory: store.copiesDirectory))

        XCTAssertFalse(reporter.hasPendingCrashReport(), "the slot is emptied once the copy is written")
        let copy = try XCTUnwrap(store.copies().first)
        XCTAssertNotNil(UUID(uuidString: copy.deletingPathExtension().lastPathComponent))
    }

    func test_aCopyThatCannotBeWritten_leavesThePendingReport() throws {
        let reporter = try reporterWithPendingReport()
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)

        XCTAssertFalse(CRXCrashBootstrap.movePendingReport(of: reporter,
                                                           toDirectory: blocker.appendingPathComponent("crashes")))

        XCTAssertTrue(reporter.hasPendingCrashReport(), "a later attempt can still copy it")
    }

    private func makeCrash(id: String, time: Date) -> MappedCrash {
        MappedCrash(crashId: id, crashTime: time, kind: .signal, exceptionType: "SIGSEGV", errorType: "SIGSEGV",
                    errorMessage: "SIGSEGV", processName: nil, applicationIdentifier: nil, pid: 1, threadsJSON: "[]",
                    triggeredByThread: nil, baseAddress: nil, arch: nil, context: nil)
    }
}
