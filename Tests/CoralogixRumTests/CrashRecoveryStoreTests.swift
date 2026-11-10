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

private final class Counter {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}

/// `adopted: false` is the id minted at image load for a session the SDK never adopted: no
/// creation time, as a crash before init leaves it.
private func crashContext(sessionId: String?, adopted: Bool = true) -> Data? {
    sessionId.map {
        adopted
            ? Data(#"{"v":1,"session":{"session_id":"\#($0)","session_creation_time":1700000000000,"is_session_sampled_in":true}}"#.utf8)
            : Data(#"{"v":1,"session":{"session_id":"\#($0)"}}"#.utf8)
    }
}

/// A real report naming `sessionId` in its crash context, the way a crash in that session leaves one.
private func liveReportData(sessionId: String?, adopted: Bool = true, exception: NSException? = nil) throws -> Data {
    let reporter = try XCTUnwrap(PLCrashReporter(configuration: PLCrashReporterConfig(signalHandlerType: .BSD,
                                                                                     symbolicationStrategy: [])))
    reporter.customData = crashContext(sessionId: sessionId, adopted: adopted)
    return try ANRThreads.withLiveReportLock {
        guard let exception else { return try reporter.generateLiveReportAndReturnError() }
        return try reporter.generateLiveReport(with: exception)
    }
}

/// The report React Native's fatal-error handler leaves. RN raises `RCTFatalException: <description>`
/// with the description as its reason; PLCrashReporter records the exception, then the process
/// aborts, so the report says SIGABRT. A live report says SIGTRAP instead, and is relabelled: both
/// names are seven bytes, so the protobuf stays valid.
private func reactNativeFatalReportData(sessionId: String, description: String) throws -> Data {
    let exception = NSException(name: NSExceptionName("RCTFatalException: \(description)"), reason: description)
    var data = try liveReportData(sessionId: sessionId, exception: exception)
    // The signal message's `name` field: tag 1, length-delimited, 7 bytes.
    let liveSignal = Data([0x0A, 0x07]) + Data("SIGTRAP".utf8)
    let range = try XCTUnwrap(data.range(of: liveSignal), "a live report records SIGTRAP")
    XCTAssertNil(data.range(of: liveSignal, in: range.upperBound..<data.endIndex), "only the signal names it")
    data.replaceSubrange(range, with: Data([0x0A, 0x07]) + Data("SIGABRT".utf8))
    return data
}

/// Leaves a crash in `store` as the load-time copy does, and returns it as recovery will read it.
@discardableResult
private func leaveCrash(in store: CrashDeliveryStore, sessionId: String?, adopted: Bool = true) throws -> MappedCrash {
    try leaveCrash(in: store, data: try liveReportData(sessionId: sessionId, adopted: adopted))
}

@discardableResult
private func leaveCrash(in store: CrashDeliveryStore, data: Data) throws -> MappedCrash {
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
                        uploader: SwitchableUploader, version: String = "9.9",
                        ignoreErrors: [String] = [],
                        instrumentations: [CoralogixExporterOptions.InstrumentationType: Bool]? = nil,
                        beforeSend: (([String: Any]) -> [String: Any]?)? = nil) throws -> CoralogixRum {
        let manager = SessionManager(snapshotStore: .relaunched(after: lastSession))
        manager.lastLaunchSession = nil
        var options = makeSamplingOptions(sampleRate: 100, exclude: [], instrumentations: instrumentations,
                                          ignoreErrors: ignoreErrors)
        options.version = version
        options.beforeSend = beforeSend
        let sdk = CoralogixRum(options: options, sessionManager: manager)
        launches.append(sdk)
        sdk.crashDeliveryStore = store
        try XCTUnwrap(sdk.coralogixExporter).spanUploader = uploader

        let clock = ManualDeliveryClock()
        let scheduler = CrashDeliveryScheduler(store: store, sender: sdk, clock: clock,
                                               backgroundTasks: FakeBackgroundTasks(), isOnline: { true })
        sdk.crashDeliveryScheduler = scheduler

        sdk.recoverPendingCrashes()
        let recovered = expectation(description: "recovery complete")
        sdk.completeCrashRecovery { recovered.fulfill() }
        // Every retry slot passes at once: what this launch cannot deliver is left for the next.
        scheduler.waitUntilAnswered()
        while let next = clock.nextDate {
            clock.advance(to: next)
            scheduler.waitUntilAnswered()
        }
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
        XCTAssertEqual(failing.crashes.count, 3, "launch 2 tried at 0 s, +30 s and +2 min")
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

    /// PLCrashReporter's single slot would have kept only the last of these. A report's time has
    /// one-second resolution, so these three usually tie: the order among equal times is not
    /// asserted here (`test_onlyTheNewestTenCopies_areKept` pins newest-first on distinct times).
    func test_threeUndeliveredCrashes_areAllSent_newestFirst() throws {
        let store = CrashDeliveryStore.temporary()
        var crashes: [MappedCrash] = []
        for session in ["S1", "S2", "S3"] {
            let crash = try leaveCrash(in: store, sessionId: session)
            store.save(.fixture(crashId: crash.crashId, sessionId: session, crashTime: crash.crashTime ?? Date(),
                                counters: sessionRecord(of: session)))
            crashes.append(crash)
        }

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: nil, uploader: uploader)

        let sessions = uploader.crashes.compactMap { value($0, .sessionContext, .sessionId) as? String }
        XCTAssertEqual(sessions.sorted(), ["S1", "S2", "S3"])
        let timeOf = Dictionary(uniqueKeysWithValues: zip(["S1", "S2", "S3"], crashes.map { $0.crashTime ?? .distantPast }))
        let sentTimes = sessions.compactMap { timeOf[$0] }
        XCTAssertEqual(sentTimes, sentTimes.sorted(by: >), "newest first")
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
        XCTAssertEqual(counts, Array(repeating: 3, count: 9),
                       "the session's two errors plus this crash, on each of 3 sends in each of 3 launches")
        XCTAssertEqual(store.record(for: crash.crashId)?.counters.errorCount, 2, "never written back")
    }

    /// The crash is rebuilt for every send, so a `beforeSend` that drops it on the retry is
    /// heard, and the crash is finished with.
    func test_everySend_runsBeforeSendAgain() throws {
        let store = CrashDeliveryStore.temporary()
        try leaveCrash(in: store, sessionId: "S1")
        let failing = SwitchableUploader()
        failing.result = SwitchableUploader.serverError
        let crashesSeen = Counter()

        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: failing, beforeSend: { event in
            let errorContext = event[Keys.errorContext.rawValue] as? [String: Any]
            guard errorContext?[Keys.isCrash.rawValue] as? Bool == true else { return event }
            return crashesSeen.increment() == 1 ? event : nil
        })

        XCTAssertEqual(crashesSeen.value, 2, "the first send and the +30 s retry")
        XCTAssertEqual(failing.crashes.count, 1)
        XCTAssertTrue(store.copies().isEmpty, "dropped by beforeSend on the retry: finished with")
    }

    /// A JS fatal in React Native reaches the next launch as the native report it left: one crash,
    /// shaped like every other aborted exception, with RN's repeated description cut from the name.
    func test_aReactNativeFatal_isSentAsOneCrash_signalShaped() throws {
        let store = CrashDeliveryStore.temporary()
        let description = "Unhandled JS Exception: TypeError: undefined is not a function"
        let data = try reactNativeFatalReportData(sessionId: "S1", description: description)
        let report = try PLCrashReport(data: data)
        let crash = try leaveCrash(in: store, data: data)

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader)

        XCTAssertEqual(uploader.crashes.count, 1)
        let sent = try XCTUnwrap(uploader.crashes.first)
        XCTAssertEqual(value(sent, .errorContext, .exceptionType) as? String, "SIGABRT")
        XCTAssertEqual(value(sent, .errorContext, .errorType) as? String, "SIGABRT")
        XCTAssertEqual(value(sent, .errorContext, .errorMessage) as? String, "RCTFatalException: \(description)")
        let threads = try XCTUnwrap(value(sent, .errorContext, .threads) as? [Any])
        XCTAssertEqual(threads.count, report.threads.count, "an exception crash sends every thread")
        XCTAssertGreaterThan(threads.count, 1)
        XCTAssertEqual(value(sent, .sessionContext, .sessionId) as? String, "S1")
        XCTAssertNil(store.record(for: crash.crashId))
        XCTAssertTrue(store.copies().isEmpty)
    }

    /// A crash before init names the id minted at image load, which the SDK never adopted.
    func test_aCrashInASessionNeverAdopted_isDropped_andItsCopyDeleted() throws {
        let store = CrashDeliveryStore.temporary()
        try leaveCrash(in: store, sessionId: "never-adopted", adopted: false)

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "some-other-session"), uploader: uploader)

        XCTAssertTrue(uploader.crashes.isEmpty)
        XCTAssertTrue(store.copies().isEmpty)
    }

    /// The record of an adopted session is written just after it starts: a crash in between
    /// is still that session's, with nothing counted yet.
    func test_aCrashInAnAdoptedSessionNotYetRecorded_isSent_withNothingCounted() throws {
        let store = CrashDeliveryStore.temporary()
        try leaveCrash(in: store, sessionId: "just-rotated")

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "some-other-session"), uploader: uploader)

        let crash = try XCTUnwrap(uploader.crashes.first)
        XCTAssertEqual(value(crash, .sessionContext, .sessionId) as? String, "just-rotated")
        XCTAssertEqual(value(crash, .snapshotContext, .errorCount) as? Int, 1, "only this crash")
    }

    /// With error reporting off, the copies made at image load are not sent, so not kept either.
    func test_withErrorsSwitchedOff_aCrashIsNeitherSentNorKept() throws {
        let store = CrashDeliveryStore.temporary()
        try leaveCrash(in: store, sessionId: "S1")

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader, instrumentations: [.errors: false])

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
        // The crash's span ends asynchronously and the SDK flushes it itself, so a flush from here
        // can run before it: wait for the upload instead.
        let sent = expectation(for: NSPredicate { _, _ in !failing.crashes.isEmpty }, evaluatedWith: nil)
        wait(for: [sent], timeout: 10)
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
        MappedCrash(crashId: id, crashTime: time, kind: .signal, exceptionType: "SIGSEGV",
                    errorMessage: "SIGSEGV", processName: nil, applicationIdentifier: nil, pid: 1, threadsJSON: "[]",
                    triggeredByThread: nil, baseAddress: nil, arch: nil, context: nil)
    }
}

// MARK: - Fatal hangs

private let thisProcessStart = ColdDetector.processStartTime().map(Date.init(timeIntervalSinceReferenceDate:))

/// The threads a hang marker carries: main first, as the watchdog captured them.
private let hangThreads = CrashReportMapper.watchdogThreadsJSON([
    CrashThread(number: 0, crashed: false, frames: [CrashStackFrame(frameNumber: "0", binary: "HostApp",
                                                                     functionAddressCalled: "0x100000010",
                                                                     base: "0x100000000", offset: "16")]),
    CrashThread(number: 1, crashed: true, frames: [])
])

private func hangMarker(session: String?, sampledIn: Bool = true, pid: Int32 = 4242,
                        processStartTime: Date? = nil,
                        detectedAt: Date = Date(timeIntervalSinceNow: -60),
                        liveDelivered: Bool = false) -> HangMarker {
    HangMarker(detectedAt: detectedAt, pid: pid, processStartTime: processStartTime,
               session: session.map { .init(id: $0, creationDate: 1_700_000_000, sampledIn: sampledIn) },
               threads: hangThreads, liveDelivered: liveDelivered)
}

extension CrashRecoveryAcrossLaunchesTests {

    private func errorType(_ crash: [String: Any]) -> String? {
        value(crash, .errorContext, .errorType) as? String
    }

    /// The process ended during the hang, before its own event left: the next launch reports it,
    /// once, in the session, on the screen and at the time it was detected.
    func test_aHangTheLaunchEndedDuring_isSentOnceByTheNextLaunch_asItHappened() throws {
        let store = CrashDeliveryStore.temporary()
        let marker = hangMarker(session: "S1")
        store.writeHangMarker(marker)

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader)

        XCTAssertEqual(uploader.crashes.count, 1)
        let anr = try XCTUnwrap(uploader.crashes.first)
        XCTAssertEqual(errorType(anr), "ANR")
        XCTAssertEqual(value(anr, .errorContext, .errorMessage) as? String, "Application Not Responding")
        XCTAssertEqual(value(anr, .errorContext, .isCrash) as? Bool, true)
        XCTAssertEqual((value(anr, .errorContext, .threads) as? [Any])?.count, 2)
        XCTAssertEqual(value(anr, .sessionContext, .sessionId) as? String, "S1")
        XCTAssertEqual(value(anr, .viewContext, .view) as? String, "Checkout")
        XCTAssertEqual(value(anr, .snapshotContext, .errorCount) as? Int, 3, "the session's two errors and this hang")
        let timestamp = try XCTUnwrap((anr[Keys.timestamp.rawValue] as? NSNumber)?.doubleValue)
        XCTAssertEqual(timestamp, marker.detectedAt.timeIntervalSince1970 * 1000, accuracy: 1)
        XCTAssertNil(store.hangMarker())
        XCTAssertTrue(store.hangs().isEmpty, "a delivered hang's file is deleted")

        let again = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S2"), uploader: again)
        XCTAssertTrue(again.crashes.isEmpty)
    }

    /// Stored hangs share the crashes' schedule: one that cannot be delivered is kept and sent later.
    func test_anUndeliveredHang_isKept_andSentByALaterLaunch() throws {
        let store = CrashDeliveryStore.temporary()
        store.writeHangMarker(hangMarker(session: "S1"))

        let failing = SwitchableUploader()
        failing.result = SwitchableUploader.serverError
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: failing)
        XCTAssertEqual(failing.crashes.count, 3, "0 s, +30 s and +2 min")
        XCTAssertEqual(store.hangs().count, 1)

        let delivering = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S2"), uploader: delivering)
        XCTAssertEqual(delivering.crashes.map(errorType), ["ANR"])
        XCTAssertEqual(value(try XCTUnwrap(delivering.crashes.first), .sessionContext, .sessionId) as? String, "S1")
    }

    func test_aHangWhoseLaunchThenCrashed_isReportedAsTheCrashAlone() throws {
        let store = CrashDeliveryStore.temporary()
        // The hang is detected first, then the same process crashes; a live report can take a
        // few seconds to write on a slow machine, so the crash time is taken after the marker.
        store.writeHangMarker(hangMarker(session: "S1", pid: getpid(), processStartTime: thisProcessStart,
                                         detectedAt: Date()))
        try leaveCrash(in: store, sessionId: "S1")

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader)

        XCTAssertEqual(uploader.crashes.count, 1)
        XCTAssertNotEqual(errorType(try XCTUnwrap(uploader.crashes.first)), "ANR")
        XCTAssertNil(store.hangMarker())
    }

    /// A pid can be reused: a later launch that happens to get the hung one's pid and crashes is
    /// told apart by when its process started.
    func test_aCrashOfAnotherLaunchWithTheSamePid_doesNotSuppressTheHang() throws {
        let store = CrashDeliveryStore.temporary()
        store.writeHangMarker(hangMarker(session: "S1", pid: getpid(),
                                         processStartTime: Date(timeIntervalSinceNow: -3600), detectedAt: Date()))
        try leaveCrash(in: store, sessionId: "S1")

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader)

        XCTAssertEqual(Set(uploader.crashes.map(errorType)), ["SIGTRAP", "ANR"])
    }

    /// A records file that cannot be read yet leaves the hang for a later launch, rather than
    /// storing a hang without its record or deleting one as orphaned.
    func test_anUnreadableRecordsFile_keepsTheHangForALaterLaunch() throws {
        let store = CrashDeliveryStore.temporary()
        let records = store.hangsDirectory.deletingLastPathComponent().appendingPathComponent("crash_delivery.json")
        try FileManager.default.createDirectory(at: records.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: records)
        store.writeHangMarker(hangMarker(session: "S1"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: records.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: records.path) }

        let locked = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: locked)
        XCTAssertTrue(locked.crashes.isEmpty)
        XCTAssertNotNil(store.hangMarker(), "the marker stays to be recorded later")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: records.path)
        let unlocked = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: unlocked)
        XCTAssertEqual(unlocked.crashes.map(errorType), ["ANR"])
    }

    /// Native crashes go first, then hangs, as Android sends them.
    func test_aCrashAndAHangOfDifferentLaunches_areBothSent_theCrashFirst() throws {
        let store = CrashDeliveryStore.temporary()
        try leaveCrash(in: store, sessionId: "S1")
        store.writeHangMarker(hangMarker(session: "S1", pid: 1, detectedAt: Date(timeIntervalSinceNow: 30)))

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader)

        XCTAssertEqual(uploader.crashes.map(errorType), ["SIGTRAP", "ANR"],
                       "the hang is the newer, and still goes after the crash")
    }

    func test_aHangItsOwnEventReported_isNotReportedAgain() throws {
        let store = CrashDeliveryStore.temporary()
        store.writeHangMarker(hangMarker(session: "S1", liveDelivered: true))

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader)

        XCTAssertTrue(uploader.crashes.isEmpty)
        XCTAssertNil(store.hangMarker())
        XCTAssertTrue(store.hangs().isEmpty)
    }

    func test_aHangInASampledOutSession_isNeitherSentNorKept() throws {
        let store = CrashDeliveryStore.temporary()
        store.writeHangMarker(hangMarker(session: "S1", sampledIn: false))

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader)

        XCTAssertTrue(uploader.crashes.isEmpty)
        XCTAssertTrue(store.hangs().isEmpty)
    }

    func test_ignoreErrorsNamingANR_dropsTheHang() throws {
        let store = CrashDeliveryStore.temporary()
        store.writeHangMarker(hangMarker(session: "S1"))

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader, ignoreErrors: ["ANR"])

        XCTAssertTrue(uploader.crashes.isEmpty)
        XCTAssertTrue(store.hangs().isEmpty)
    }

    func test_aHangInASessionNeverAdopted_isDropped() throws {
        let store = CrashDeliveryStore.temporary()
        store.writeHangMarker(HangMarker(detectedAt: Date(timeIntervalSinceNow: -60), pid: 4242,
                                         session: .init(id: "never-adopted", creationDate: nil, sampledIn: nil),
                                         threads: nil, liveDelivered: false))

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S2"), uploader: uploader)

        XCTAssertTrue(uploader.crashes.isEmpty)
        XCTAssertNil(store.hangMarker())
        XCTAssertTrue(store.hangs().isEmpty)
    }

    func test_withANRsSwitchedOff_aHangIsNotSent() throws {
        let store = CrashDeliveryStore.temporary()
        store.writeHangMarker(hangMarker(session: "S1"))

        let uploader = SwitchableUploader()
        try launch(store: store, lastSession: sessionRecord(of: "S1"), uploader: uploader, instrumentations: [.anr: false])

        XCTAssertTrue(uploader.crashes.isEmpty)
        XCTAssertNil(store.hangMarker())
    }
}

// MARK: - The hang marker while the app runs

final class FatalHangWatchTests: XCTestCase {

    private final class Observer: HangObserving {
        private let lock = NSLock()
        private var _calls: [String] = []
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
        func hangDetected(at date: Date, threads: String?) { lock.lock(); _calls.append("detected"); lock.unlock() }
        func hangEnded() { lock.lock(); _calls.append("ended"); lock.unlock() }
    }

    func test_theMarker_isWrittenAtDetection_andClearedWhenMainAnswers() throws {
        let store = CrashDeliveryStore.temporary()
        let watch = FatalHangWatch(store: store) { .init(id: "S1", creationDate: 1, sampledIn: true) }

        watch.hangDetected(at: Date(timeIntervalSince1970: 1_700_000_000), threads: "[]")

        let marker = try XCTUnwrap(store.hangMarker())
        XCTAssertEqual(marker.session?.id, "S1")
        XCTAssertEqual(marker.pid, getpid())
        XCTAssertEqual(marker.threads, "[]")
        XCTAssertFalse(marker.liveDelivered)

        watch.hangEnded()
        XCTAssertNil(store.hangMarker())
    }

    func test_theWatchdog_tellsTheObserverOfAReportedHang_andOfItsEnd() {
        let main = DispatchQueue(label: "hang-watch.main")
        let observer = Observer()
        let detector = ANRDetector(threshold: 0.5, pollInterval: 0.05, mainQueue: main, isDebuggerAttached: { false },
                                   captureThreads: { nil }, notificationCenter: NotificationCenter(),
                                   hangObserver: observer)
        detector.startMonitoring()
        defer { detector.stopMonitoring() }
        Thread.sleep(forTimeInterval: 0.2)

        main.async { Thread.sleep(forTimeInterval: 1.0) }
        main.sync {}
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(observer.calls, ["detected", "ended"])
    }

    /// Stopped (shutdown, re-init) during a hang it reported, the watchdog still ends that hang
    /// once the main thread answers, so the next launch does not take it for a fatal one.
    func test_stoppedDuringAReportedHang_theHangStillEndsWhenMainAnswers() {
        let main = DispatchQueue(label: "hang-watch.main")
        let observer = Observer()
        let detector = ANRDetector(threshold: 0.5, pollInterval: 0.05, mainQueue: main, isDebuggerAttached: { false },
                                   captureThreads: { nil }, notificationCenter: NotificationCenter(),
                                   hangObserver: observer)
        detector.startMonitoring()
        Thread.sleep(forTimeInterval: 0.2)

        main.async { Thread.sleep(forTimeInterval: 1.0) }
        Thread.sleep(forTimeInterval: 0.8)
        detector.stopMonitoring()
        XCTAssertEqual(observer.calls, ["detected"])
        main.sync {}
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertEqual(observer.calls.first, "detected")
        XCTAssertEqual(observer.calls.last, "ended")
    }

    func test_aHangUnderADebugger_leavesNoMarker() {
        let main = DispatchQueue(label: "hang-watch.main")
        let observer = Observer()
        let detector = ANRDetector(threshold: 0.5, pollInterval: 0.05, mainQueue: main, isDebuggerAttached: { true },
                                   captureThreads: { nil }, notificationCenter: NotificationCenter(),
                                   hangObserver: observer)
        detector.startMonitoring()
        defer { detector.stopMonitoring() }
        Thread.sleep(forTimeInterval: 0.2)

        main.async { Thread.sleep(forTimeInterval: 1.0) }
        main.sync {}
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertTrue(observer.calls.isEmpty)
    }

    /// The hang's own event is matched to its delivery by span id, so a delivered ANR is not
    /// reported a second time if the process then ends during the hang.
    func test_theHangsOwnEvent_delivered_marksTheMarker_andRefused_doesNot() throws {
        for (result, delivered) in [(SpanUploadResult.delivered, true), (SpanUploadResult.permanentReject, false)] {
            let store = CrashDeliveryStore.temporary()
            let sdk = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
            defer { sdk.shutdown() }
            let exporter = try XCTUnwrap(sdk.coralogixExporter)
            exporter.spanUploader = FixedUploader(result: result)
            let watch = FatalHangWatch(store: store) { .init(id: "S1", creationDate: 1, sampledIn: true) }
            watch.hangDetected(at: Date(), threads: nil)

            let span = sdk.makeSpan(event: .error, source: .code, severity: .error)
            span.setAttribute(key: Keys.errorType.rawValue, value: "ANR")
            span.setAttribute(key: Keys.errorMessage.rawValue, value: "Application Not Responding for at least 1000 ms.")
            let answered = expectation(description: "answered")
            watch.awaitDelivery(ofSpan: span.context.spanId.hexString, through: exporter)
            exporter.awaitLiveDelivery(spanId: "unrelated") { _ in }
            span.end()
            sdk.flush { answered.fulfill() }
            wait(for: [answered], timeout: 10)

            XCTAssertEqual(store.hangMarker()?.liveDelivered, delivered, "upload \(result.disposition)")
        }
    }
}

final class CustomSessionManagerCrashContextTests: XCTestCase {
    /// A SessionManager the host app passes in still names its session in every crash report.
    func test_aSessionManagerPassedIn_writesItsSessionIntoTheCrashContext() throws {
        let saved = CRXCrashContext.sections
        defer {
            for (name, value) in saved { CRXCrashContext.setSection(name, value: value as? [String: Any]) }
        }
        let manager = SessionManager()
        let sdk = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []), sessionManager: manager)
        defer { sdk.shutdown() }

        let session = try XCTUnwrap(CRXCrashContext.sections[Keys.crashContextSession.rawValue] as? [String: Any])
        XCTAssertEqual(session[Keys.sessionId.rawValue] as? String, manager.sessionMetadata?.sessionId)
    }
}

private final class FixedUploader: SpanUploading {
    let result: SpanUploadResult
    init(result: SpanUploadResult) { self.result = result }
    func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult { result }
}
