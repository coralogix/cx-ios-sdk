//
//  CrashedSessionTests.swift
//
//  A crash is reported under the session it happened in, with the view, counters and versions
//  that session had. The session comes from the crash context written into the report; the rest
//  from that session's record, which is kept current from the moment the SDK adopts the session.
//

import XCTest
import CrashReporter
import CoralogixInternal
#if canImport(CoralogixBootstrap)
import CoralogixBootstrap
#endif

@testable import Coralogix

// MARK: - Launch session and crash stamp

final class LaunchSessionTests: XCTestCase {

    override func tearDown() {
        CRXCrashBootstrap.resetLaunchSessionClaimForTesting()
        super.tearDown()
    }

    func test_theLaunchSession_isClaimedExactlyOnce() throws {
        CRXCrashBootstrap.resetLaunchSessionClaimForTesting()

        let first = try XCTUnwrap(CRXCrashBootstrap.claimLaunchSession(), "+load minted a launch session")
        XCTAssertFalse(first.isEmpty)
        XCTAssertNil(CRXCrashBootstrap.claimLaunchSession())
    }

    func test_theFirstSession_adoptsTheSeed_andLaterOnesMintTheirOwn() {
        let manager = SessionManager(snapshotStore: SessionSnapshotStore(keychain: MockKeyChain()),
                                     launchSessionId: "seed-session")
        XCTAssertEqual(manager.currentSessionId, "seed-session")

        manager.setupSessionMetadata()

        XCTAssertNotEqual(manager.currentSessionId, "seed-session")
        XCTAssertNotNil(manager.currentSessionId)
    }

    func test_theCrashStamp_followsAdoption_samplingAndRotation_inOrder() throws {
        var stamps: [SessionManager.CrashStamp] = []
        let manager = SessionManager(snapshotStore: SessionSnapshotStore(keychain: MockKeyChain()),
                                     launchSessionId: "seed-session",
                                     crashStampObserver: { stamps.append($0) })
        manager.setSessionSampledIn(false)
        manager.samplingRoller = { true }
        manager.setupSessionMetadata()

        XCTAssertEqual(stamps.map(\.sessionId).prefix(2), ["seed-session", "seed-session"])
        XCTAssertEqual(stamps.map(\.sampledIn), [true, false, true])
        let rotated = try XCTUnwrap(stamps.last)
        XCTAssertEqual(rotated.sessionId, manager.currentSessionId)
        XCTAssertGreaterThan(rotated.creationDate, 0)
    }

    func test_aDetachedObserver_hearsNoMoreSessions() {
        var stamps: [SessionManager.CrashStamp] = []
        let manager = SessionManager(snapshotStore: SessionSnapshotStore(keychain: MockKeyChain()),
                                     crashStampObserver: { stamps.append($0) })
        manager.detachCrashStampObserver()

        manager.setupSessionMetadata()

        XCTAssertEqual(stamps.count, 1, "only the first session, before the detach")
    }

    func test_theCrashContext_namesTheLiveSession() throws {
        let saved = CRXCrashContext.sections
        defer {
            CRXCrashContext.setSection(Keys.crashContextSession.rawValue,
                                       value: saved[Keys.crashContextSession.rawValue] as? [String: Any])
        }
        CrashContextSession.write(.init(sessionId: "live-session", creationDate: 1_700_000_000.5, sampledIn: false))

        let session = try XCTUnwrap(CrashContextEnvelope(data: CrashContextTests.liveReport().customData)?.session)
        XCTAssertEqual(session, .init(id: "live-session", creationTimeMillis: 1_700_000_000_500, sampledIn: false))
    }
}

// MARK: - The live session's record

final class LiveSessionRecordTests: XCTestCase {

    private var rum: CoralogixRum?

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        try super.tearDownWithError()
    }

    private func start(sampleRate: Int = 100,
                       exclude: Set<ExcludableInstrumentation> = [],
                       version: String = "1.0.0") throws -> (CoralogixRum, SessionManager, CoralogixExporter) {
        let manager = SessionManager(snapshotStore: SessionSnapshotStore(keychain: MockKeyChain()))
        var options = makeSamplingOptions(sampleRate: sampleRate, exclude: exclude)
        options.version = version
        let sdk = CoralogixRum(options: options, sessionManager: manager)
        rum = sdk
        let exporter = try XCTUnwrap(sdk.coralogixExporter)
        exporter.sessionRecorder.waitForPendingWrites()
        return (sdk, manager, exporter)
    }

    private func record(_ manager: SessionManager, _ exporter: CoralogixExporter) throws -> SessionSnapshotRecord {
        exporter.sessionRecorder.waitForPendingWrites()
        let id = try XCTUnwrap(manager.currentSessionId)
        return try XCTUnwrap(manager.snapshotStore.record(for: id), "the live session has a record")
    }

    func test_noRecordBeforeAdoption_oneRightAfter() throws {
        let manager = SessionManager(snapshotStore: SessionSnapshotStore(keychain: MockKeyChain()))
        let id = try XCTUnwrap(manager.currentSessionId)
        XCTAssertNil(manager.snapshotStore.record(for: id), "a session the SDK never adopted has no record")

        let sdk = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []), sessionManager: manager)
        rum = sdk
        let exporter = try XCTUnwrap(sdk.coralogixExporter)

        let adopted = try record(manager, exporter)
        XCTAssertEqual(adopted.errorCount, 0)
        XCTAssertEqual(adopted.actionCount, 0)
        XCTAssertNil(adopted.viewName)
        XCTAssertEqual(adopted.appName, "TestApp")
        XCTAssertEqual(adopted.appVersion, "1.0.0")
        XCTAssertEqual(adopted.osVersion, Global.osVersionInfo())
    }

    func test_clicksWithNoSnapshot_areRecorded() throws {
        let (_, manager, exporter) = try start()

        (1...3).forEach { _ in manager.incrementClickCounter() }

        XCTAssertEqual(try record(manager, exporter).actionCount, 3)
    }

    func test_aViewChange_isRecorded() throws {
        let (_, manager, exporter) = try start()

        exporter.set(cxView: CXView(state: .notifyOnAppear, name: "Checkout"))
        exporter.set(cxView: CXView(state: .notifyOnAppear, name: "Payment"))

        let current = try record(manager, exporter)
        XCTAssertEqual(current.viewName, "Payment")
        XCTAssertEqual(current.viewNumber, 1)
        XCTAssertEqual(current.viewCount, 2)
    }

    func test_rotatingOnAScreen_recordsItAsViewZeroOfTheNewSession() throws {
        let (_, manager, exporter) = try start()
        exporter.set(cxView: CXView(state: .notifyOnAppear, name: "Checkout"))
        manager.incrementClickCounter()
        let before = try XCTUnwrap(manager.currentSessionId)

        manager.setupSessionMetadata()

        let rotated = try record(manager, exporter)
        XCTAssertNotEqual(rotated.sessionId, before)
        XCTAssertEqual(rotated.viewName, "Checkout")
        XCTAssertEqual(rotated.viewNumber, 0)
        XCTAssertEqual(rotated.actionCount, 0, "the new session's counters start over")
        XCTAssertEqual(manager.snapshotStore.record(for: before)?.actionCount, 1, "the ended session keeps its record")
    }

    func test_anAppContextChange_isRecorded() throws {
        let (sdk, manager, exporter) = try start()

        sdk.setApplicationContext(application: "Renamed", version: "2.0.0")

        let current = try record(manager, exporter)
        XCTAssertEqual(current.appName, "Renamed")
        XCTAssertEqual(current.appVersion, "2.0.0")
    }

    func test_aSampledOutSession_stillHasARecord() throws {
        let (_, manager, exporter) = try start(sampleRate: 0, exclude: [.errors])
        XCTAssertFalse(manager.isSessionSampledIn)

        XCTAssertNotNil(try record(manager, exporter))
    }

    func test_aSnapshotsCounters_keepTheRecordedView() {
        let store = SessionSnapshotStore(keychain: MockKeyChain())
        store.persist(SessionSnapshotRecord(sessionId: "s", errorCount: 0, viewCount: 1, actionCount: 0,
                                            hasRecording: false, viewName: "Home", viewNumber: 0,
                                            appName: "App", appVersion: "1", osVersion: "17.0"))

        store.persistCounters(SessionSnapshotRecord(sessionId: "s", errorCount: 2, viewCount: 1,
                                                    actionCount: 5, hasRecording: false))

        let record = store.record(for: "s")
        XCTAssertEqual(record?.errorCount, 2)
        XCTAssertEqual(record?.actionCount, 5)
        XCTAssertEqual(record?.viewName, "Home")
        XCTAssertEqual(record?.appVersion, "1")
    }

    func test_aRecordFromAnEarlierVersion_decodes() throws {
        let keychain = MockKeyChain()
        keychain.writeStringToKeychain(service: Keys.service.rawValue, key: Keys.keySessionSnapshot.rawValue,
                                       value: #"{"sessionId":"old","errorCount":1,"viewCount":2,"actionCount":3,"hasRecording":true}"#)

        let record = try XCTUnwrap(SessionSnapshotStore(keychain: keychain).record(for: "old"))

        XCTAssertEqual(record.actionCount, 3)
        XCTAssertNil(record.viewName)
        XCTAssertNil(record.appVersion)
    }
}

// MARK: - Recovery

final class CrashedSessionRecoveryTests: XCTestCase {

    private var rum: CoralogixRum?

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        try super.tearDownWithError()
    }

    private struct Report: CrashReportReading {
        var reportId: String? = "5A1B2C3D-0000-4000-8000-000000000001"
        var timestamp: Date? = Date(timeIntervalSince1970: 1_700_000_100)
        var signalName = "SIGSEGV"
        var signalCode: String? = "SEGV_MAPERR"
        var exceptionName: String?
        var exceptionReason: String?
        var processName: String? = "HostApp"
        var processID: UInt = 7
        var applicationIdentifier: String? = "com.example.host"
        var threads: [CrashThread] = [CrashThread(number: 0, crashed: true, frames: [])]
        var mainBinaryImage: (baseAddress: String, arch: String)? = ("0x100000000", "arm64")
        var customData: Data?

        static func naming(_ sessionId: String?) -> Report {
            var report = Report()
            report.customData = sessionId.map {
                Data(#"{"v":1,"session":{"session_id":"\#($0)","session_creation_time":1700000000000,"is_session_sampled_in":true}}"#.utf8)
            }
            return report
        }
    }

    private let crashedRecord = SessionSnapshotRecord(sessionId: "S1", errorCount: 2, viewCount: 3, actionCount: 4,
                                                      hasRecording: false, viewName: "Checkout", viewNumber: 2,
                                                      appName: "TestApp", appVersion: "1.0-crashed", osVersion: "17.0")

    /// A relaunch whose store holds `record` from the launch before, and whose keychain says the
    /// previous launch's session was `keychainSession`.
    private func relaunch(after record: SessionSnapshotRecord?,
                          keychainSession: String? = "S2",
                          tracesExporter: TracesExporterCallback? = nil) throws -> CoralogixRum {
        let manager = SessionManager(snapshotStore: .relaunched(after: record))
        manager.lastLaunchSession = keychainSession.map {
            LastLaunchSession(sessionId: $0, creationDate: 1_600_000_000, sampledIn: true)
        }
        var options = makeSamplingOptions(sampleRate: 100, exclude: [], tracesExporter: tracesExporter)
        options.version = "2.0-relaunch"
        let sdk = CoralogixRum(options: options, sessionManager: manager)
        rum = sdk
        return sdk
    }

    private func attributes(of crash: MappedCrash, in sdk: CoralogixRum) throws -> [String: AttributeValue] {
        let span = sdk.makeSpan(event: .error, source: .console, severity: .error, startsNewTrace: true)
        defer { span.end() }
        sdk.attribute(span, to: sdk.crashedSession(of: crash))
        return try XCTUnwrap((span as? any ReadableSpan)?.toSpanData()).attributes
    }

    func test_theReportsSession_winsOverTheKeychains() throws {
        let sdk = try relaunch(after: crashedRecord, keychainSession: "S2")
        sdk.coralogixExporter?.getViewManager().prevViewName = "SomeOtherScreen"

        let attributes = try attributes(of: CrashReportMapper.map(Report.naming("S1")), in: sdk)

        XCTAssertEqual(attributes[Keys.sessionId.rawValue]?.description, "S1")
        XCTAssertEqual(attributes[Keys.sessionCreationDate.rawValue]?.description, "1700000000")
        XCTAssertEqual(attributes[Keys.spanViewName.rawValue]?.description, "Checkout",
                       "the view is the crashed session's, not the last view the keychain saw")
        XCTAssertEqual(attributes[Keys.spanViewNumber.rawValue]?.description, "2")
        XCTAssertEqual(attributes[Keys.crashedAppVersion.rawValue]?.description, "1.0-crashed")
        XCTAssertEqual(attributes[Keys.crashedOsVersion.rawValue]?.description, "17.0")
    }

    func test_aReportNamingASessionWithNoRecord_neverFallsBackToTheKeychain() throws {
        let sdk = try relaunch(after: nil, keychainSession: "S2")

        let attributes = try attributes(of: CrashReportMapper.map(Report.naming("S1")), in: sdk)

        XCTAssertEqual(attributes[Keys.sessionId.rawValue]?.description, "S1")
        XCTAssertEqual(attributes[Keys.spanViewName.rawValue]?.description, Keys.undefined.rawValue)
        XCTAssertNil(attributes[Keys.spanViewNumber.rawValue])
        XCTAssertNil(attributes[Keys.crashedAppVersion.rawValue])
    }

    func test_anOldReport_withoutContext_usesTheKeychainSession() throws {
        let keychainRecord = SessionSnapshotRecord(sessionId: "S2", errorCount: 1, viewCount: 1, actionCount: 1,
                                                   hasRecording: false)
        let sdk = try relaunch(after: keychainRecord, keychainSession: "S2")

        let crash = CrashReportMapper.map(Report.naming(nil))
        XCTAssertEqual(sdk.crashedSession(of: crash)?.record, keychainRecord)
        let attributes = try attributes(of: crash, in: sdk)

        XCTAssertEqual(attributes[Keys.sessionId.rawValue]?.description, "S2")
        XCTAssertEqual(attributes[Keys.sessionCreationDate.rawValue]?.description, "1600000000")
    }

    func test_aCrashBeforeTheFirstView_hasAnEmptyView_andNoViewNumber() throws {
        var noView = crashedRecord
        noView.viewName = nil
        noView.viewNumber = nil
        let sdk = try relaunch(after: noView)

        let attributes = try attributes(of: CrashReportMapper.map(Report.naming("S1")), in: sdk)

        XCTAssertEqual(attributes[Keys.spanViewName.rawValue]?.description, Keys.undefined.rawValue)
        XCTAssertNil(attributes[Keys.spanViewNumber.rawValue])
    }

    // MARK: - On the wire

    private final class RecordingUploader: SpanUploading {
        private let lock = NSLock()
        private var _events: [[String: Any]] = []
        var events: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return _events }

        func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
            lock.lock(); defer { lock.unlock() }
            _events.append(contentsOf: spans)
            return .delivered
        }
    }

    func test_aRecoveredCrash_reportsTheSessionViewAndVersionsItCrashedUnder() throws {
        let sdk = try relaunch(after: crashedRecord)
        let exporter = try XCTUnwrap(sdk.coralogixExporter)
        let uploader = RecordingUploader()
        exporter.spanUploader = uploader

        sdk.emitRecoveredCrash(CrashReportMapper.map(Report.naming("S1")))
        let flushed = expectation(description: "flushed")
        sdk.flush { flushed.fulfill() }
        wait(for: [flushed], timeout: 10)

        let cxRum = try XCTUnwrap(uploader.events.lazy.compactMap { event -> [String: Any]? in
            let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
            let errorContext = cxRum?[Keys.errorContext.rawValue] as? [String: Any]
            return errorContext?[Keys.isCrash.rawValue] as? Bool == true ? cxRum : nil
        }.first)
        let session = cxRum[Keys.sessionContext.rawValue] as? [String: Any]
        let view = cxRum[Keys.viewContext.rawValue] as? [String: Any]
        let versions = cxRum[Keys.versionMetaData.rawValue] as? [String: Any]
        let device = cxRum[Keys.deviceContext.rawValue] as? [String: Any]
        XCTAssertEqual(session?[Keys.sessionId.rawValue] as? String, "S1")
        XCTAssertEqual(view?[Keys.view.rawValue] as? String, "Checkout")
        XCTAssertEqual(versions?[Keys.appVersion.rawValue] as? String, "1.0-crashed")
        XCTAssertEqual(device?[Keys.osVersion.rawValue] as? String, "17.0")
    }
}
