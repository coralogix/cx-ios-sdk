//
//  CrashReportRecoveryTests.swift
//
//  The native crash flow: PLCrashReporter captures a report when the process
//  dies, and on the *next* launch `initializeCrashInstrumentation` parses it,
//  emits a crash span, and defers purging the report until `completeCrashRecovery`
//  confirms the span actually uploaded (at-least-once delivery). These tests drive
//  that flow without a real crash:
//   - `emitCrashSpan` is exercised with a genuine report from `generateLiveReport()`
//   - the orchestration + purge-gating is driven through a `FakeCrashReporter`,
//     injected via `CoralogixRum.crashReporterProvider`
//

import XCTest
import CoralogixInternal
import CrashReporter
import Foundation

@testable import Coralogix

final class CrashReportRecoveryTests: XCTestCase {

    private var coralogixRum: CoralogixRum!

    override func tearDownWithError() throws {
        CoralogixRum.crashReporterProvider = nil
        CoralogixExporter.testExportCallback = nil
        coralogixRum?.shutdown()
        coralogixRum = nil
    }

    // MARK: - Fixtures

    /// Records every uploaded batch and returns a configurable result.
    private final class StubUploader: SpanUploading {
        var result: SpanExporterResultCode = .success
        private(set) var uploadedBatches: [[[String: Any]]] = []
        func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
            uploadedBatches.append(spans)
            return result
        }
    }

    /// A `CrashReporting` seam that hands back canned report data and records
    /// whether the pending report was purged.
    private final class FakeCrashReporter: CrashReporting {
        var pending: Bool
        var reportData: Data
        var loadError: Error?
        private(set) var purgeCount = 0

        init(reportData: Data, pending: Bool = true) {
            self.reportData = reportData
            self.pending = pending
        }

        func hasPendingCrashReport() -> Bool { pending }

        func loadPendingCrashReportDataAndReturnError() throws -> Data {
            if let loadError { throw loadError }
            return reportData
        }

        @discardableResult
        func purgePendingCrashReport() -> Bool {
            purgeCount += 1
            pending = false
            return true
        }
    }

    /// A real, valid PLCrashReport captured from the live process — same wire
    /// format as a report written on an actual crash, but without dying.
    private func makeLiveReportData() throws -> Data {
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all)
        let reporter = try XCTUnwrap(PLCrashReporter(configuration: config))
        return try XCTUnwrap(reporter.generateLiveReport(), "generateLiveReport returned nil")
    }

    /// A committed fixture captured from a *real* `abort()` crash (SIGABRT) with
    /// PLCrashReporter installed — a genuine on-disk crash report, unlike a live
    /// report which carries a synthetic signal and a ~now timestamp.
    private func loadRealCrashReportData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "real_crash", withExtension: "plcrash"),
                                "real_crash.plcrash fixture missing from the test bundle")
        return try Data(contentsOf: url)
    }

    private func makeTempStore() -> CrashEventStore {
        CrashEventStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    /// Force-exports queued spans and blocks until the flush completion runs, so the
    /// crash-recovery purge decision (which runs inside that completion) has happened.
    private func flushAndWait() {
        let done = expectation(description: "flush")
        coralogixRum.flush { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    // MARK: - Parse + emit (emitCrashSpan)

    func test_emitCrashSpan_fromLiveReport_stampsCrashAttributesOnRawSpan() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        coralogixRum.coralogixExporter?.spanUploader = StubUploader()

        var crashSpan: SpanData?
        CoralogixExporter.testExportCallback = { spans in
            if let span = spans.first(where: { $0.attributes[Keys.crashEventId.rawValue]?.description == "live-report" }) {
                crashSpan = span
            }
        }

        XCTAssertTrue(coralogixRum.emitCrashSpan(fromReportData: try makeLiveReportData(),
                                                 crashEventId: "live-report"),
                      "a valid report must parse and emit a span")
        flushAndWait()

        let span = try XCTUnwrap(crashSpan, "the crash span must reach the exporter")
        XCTAssertEqual(span.attributes[Keys.eventType.rawValue]?.description, CoralogixEventType.error.rawValue)
        // The raw is_crash marker is what the exporter reads to confirm the upload
        // and gate the report purge — the encoded is_crash is off the wire there.
        XCTAssertEqual(span.attributes[Keys.isCrash.rawValue]?.description, "true",
                       "the native crash span must carry the raw is_crash marker")
        XCTAssertEqual(span.attributes[Keys.crashEventId.rawValue]?.description, "live-report")
        XCTAssertFalse((span.attributes[Keys.processName.rawValue]?.description ?? "").isEmpty,
                       "process name must be parsed from the report")
        XCTAssertFalse((span.attributes[Keys.pid.rawValue]?.description ?? "").isEmpty,
                       "pid must be parsed from the report")
        XCTAssertFalse((span.attributes[Keys.threads.rawValue]?.description ?? "").isEmpty,
                       "thread stack traces must be parsed from the report")
    }

    func test_emitCrashSpan_fromRealCrashReport_stampsRealSignalAndPastCrashTime() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        coralogixRum.coralogixExporter?.spanUploader = StubUploader()

        let data = try loadRealCrashReportData()
        let crashTime = try XCTUnwrap(PLCrashReport(data: data).systemInfo.timestamp,
                                      "the fixture must carry the crash timestamp")

        var crashSpan: SpanData?
        CoralogixExporter.testExportCallback = { spans in
            if let span = spans.first(where: { $0.attributes[Keys.crashEventId.rawValue]?.description == "fixture" }) {
                crashSpan = span
            }
        }

        XCTAssertTrue(coralogixRum.emitCrashSpan(fromReportData: data, crashEventId: "fixture"))
        flushAndWait()

        let span = try XCTUnwrap(crashSpan)
        // The genuine signal that killed the process — a live report can't produce this.
        XCTAssertEqual(span.attributes[Keys.exceptionType.rawValue]?.description, "SIGABRT",
                       "crash span must carry the real signal from the crash report")
        XCTAssertEqual(span.attributes[Keys.processName.rawValue]?.description, "CrashFixtureGen")
        XCTAssertEqual(span.attributes[Keys.isCrash.rawValue]?.description, "true")
        XCTAssertFalse((span.attributes[Keys.threads.rawValue]?.description ?? "").isEmpty)
        // The crash was captured in the past; the span must be anchored to that crash
        // time, strictly before this (relaunch) test run — not stamped with Date().
        XCTAssertEqual(span.startTime, crashTime,
                       "crash span must start at the crash time recorded in the report")
        XCTAssertLessThan(crashTime, Date(),
                          "the crash time must precede the relaunch time — proving it's not a now/relaunch stamp")
        XCTAssertEqual(span.attributes[Keys.crashTimestamp.rawValue]?.description,
                       "\(crashTime.timeIntervalSince1970.milliseconds)")
    }

    func test_emitCrashSpan_anchorsSpanToCrashTime_notRelaunchTime() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        coralogixRum.coralogixExporter?.spanUploader = StubUploader()

        let data = try makeLiveReportData()
        // The crash time lives inside the report; read it the same way production does.
        // A relaunch-time implementation would instead stamp Date() when the span is built.
        let crashTime = try XCTUnwrap(PLCrashReport(data: data).systemInfo.timestamp,
                                      "the report must carry a crash timestamp")

        var crashSpan: SpanData?
        CoralogixExporter.testExportCallback = { spans in
            if let span = spans.first(where: { $0.attributes[Keys.crashEventId.rawValue]?.description == "ts" }) {
                crashSpan = span
            }
        }

        XCTAssertTrue(coralogixRum.emitCrashSpan(fromReportData: data, crashEventId: "ts"))
        flushAndWait()

        let span = try XCTUnwrap(crashSpan)
        XCTAssertEqual(span.startTime, crashTime,
                       "crash span must start at the crash time from the report, not the relaunch time")
        XCTAssertEqual(span.endTime, crashTime,
                       "crash span must end at the crash time — a relaunch-stamped span would end later than it started")
        XCTAssertEqual(span.attributes[Keys.crashTimestamp.rawValue]?.description,
                       "\(crashTime.timeIntervalSince1970.milliseconds)",
                       "crash_timestamp must be the crash time in ms")
    }

    func test_emitCrashSpan_attributesToCrashedSession_notRelaunchSession() throws {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let sessionManager = try XCTUnwrap(coralogixRum.coralogixExporter?.getSessionManager())

        // The relaunch (current) session, plus the session that was live when the crash
        // happened — recovered from the keychain into the old* fields on relaunch.
        var metadata = SessionMetadata(sessionId: "relaunch_session",
                                       sessionCreationDate: Date().timeIntervalSince1970,
                                       using: MockKeyChain())
        metadata.oldSessionId = "crashed_session_id"
        metadata.oldSessionTimeInterval = 1_700_000_000
        sessionManager.sessionMetadata = metadata

        coralogixRum.coralogixExporter?.spanUploader = StubUploader()
        var crashSpan: SpanData?
        CoralogixExporter.testExportCallback = { spans in
            if let span = spans.first(where: { $0.attributes[Keys.crashEventId.rawValue]?.description == "sess" }) {
                crashSpan = span
            }
        }

        XCTAssertTrue(coralogixRum.emitCrashSpan(fromReportData: try makeLiveReportData(), crashEventId: "sess"))
        flushAndWait()

        // makeSpan stamps the current (relaunch) session; overrideSessionForCrashedSession
        // must replace it with the crashed session. SessionContext serializes this exact
        // span attribute to the wire, so this is what the platform receives.
        let span = try XCTUnwrap(crashSpan)
        XCTAssertEqual(span.attributes[Keys.sessionId.rawValue]?.description, "crashed_session_id",
                       "crash span must carry the session that was live at crash time")
        XCTAssertNotEqual(span.attributes[Keys.sessionId.rawValue]?.description, "relaunch_session",
                          "crash span must NOT be attributed to the freshly-created relaunch session")
        XCTAssertEqual(span.attributes[Keys.sessionCreationDate.rawValue]?.description, "1700000000",
                       "crash span must carry the crashed session's creation date")
    }

    func test_emitCrashSpan_withUnparseableData_returnsFalse_andEmitsNoSpan() {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        coralogixRum.coralogixExporter?.spanUploader = StubUploader()

        var emittedCrash = false
        CoralogixExporter.testExportCallback = { spans in
            if spans.contains(where: { $0.attributes[Keys.crashEventId.rawValue] != nil }) { emittedCrash = true }
        }

        XCTAssertFalse(coralogixRum.emitCrashSpan(fromReportData: Data("not a crash report".utf8),
                                                  crashEventId: "bad"),
                       "unparseable data must not emit a span")
        flushAndWait()
        XCTAssertFalse(emittedCrash)
    }

    // MARK: - Relaunch orchestration + purge gating

    /// Builds a CoralogixRum with the fake wired in, but with no pending report at
    /// construction time so init-time recovery is a clean no-op. Callers then flip
    /// `pending` and drive recovery explicitly against a stub uploader.
    private func makeRumWithFake(_ fake: FakeCrashReporter, uploaderResult: SpanExporterResultCode) -> StubUploader {
        fake.pending = false
        CoralogixRum.crashReporterProvider = { fake }
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let uploader = StubUploader()
        uploader.result = uploaderResult
        coralogixRum.coralogixExporter?.spanUploader = uploader
        coralogixRum.crashEventStore = makeTempStore()
        fake.pending = true
        return uploader
    }

    func test_pendingNativeReport_purgedAfterConfirmedUpload() throws {
        let fake = FakeCrashReporter(reportData: try makeLiveReportData())
        _ = makeRumWithFake(fake, uploaderResult: .success)

        coralogixRum.initializeCrashInstrumentation()
        coralogixRum.completeCrashRecovery()

        XCTAssertTrue(waitUntil { fake.purgeCount == 1 },
                      "a confirmed crash upload must purge the pending report exactly once")
    }

    func test_pendingNativeReport_keptWhenUploadFails() throws {
        let fake = FakeCrashReporter(reportData: try makeLiveReportData())
        let uploader = makeRumWithFake(fake, uploaderResult: .failure)

        coralogixRum.initializeCrashInstrumentation()
        coralogixRum.completeCrashRecovery()

        XCTAssertTrue(waitUntil { !uploader.uploadedBatches.isEmpty },
                      "recovery must attempt the upload")
        // Let the flush completion (which decides whether to purge) settle.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(fake.purgeCount, 0,
                       "an unconfirmed crash upload must keep the pending report for the next launch")
        XCTAssertTrue(fake.pending)
    }

    func test_pendingReport_thatFailsToParse_isPurgedImmediately_withoutSpan() throws {
        let fake = FakeCrashReporter(reportData: try makeLiveReportData())
        _ = makeRumWithFake(fake, uploaderResult: .success)
        fake.reportData = Data("corrupt".utf8)

        var emittedCrash = false
        CoralogixExporter.testExportCallback = { spans in
            if spans.contains(where: { $0.attributes[Keys.crashEventId.rawValue] != nil }) { emittedCrash = true }
        }

        coralogixRum.initializeCrashInstrumentation()

        XCTAssertEqual(fake.purgeCount, 1,
                       "a report that can't be parsed must be dropped so it isn't re-processed every launch")
        flushAndWait()
        XCTAssertFalse(emittedCrash, "no crash span should be emitted for an unparseable report")
    }

    func test_pendingReport_thatFailsToLoad_isPurgedImmediately_withoutSpan() throws {
        let fake = FakeCrashReporter(reportData: try makeLiveReportData())
        _ = makeRumWithFake(fake, uploaderResult: .success)
        // Exercises the load-failure branch (distinct from a parse failure): the
        // reporter reports a pending crash but hands back an error, not data.
        fake.loadError = NSError(domain: "test", code: 1)

        var emittedCrash = false
        CoralogixExporter.testExportCallback = { spans in
            if spans.contains(where: { $0.attributes[Keys.crashEventId.rawValue] != nil }) { emittedCrash = true }
        }

        coralogixRum.initializeCrashInstrumentation()

        XCTAssertEqual(fake.purgeCount, 1,
                       "a report that can't be loaded must be dropped so it isn't re-processed every launch")
        flushAndWait()
        XCTAssertFalse(emittedCrash, "no crash span should be emitted when the report can't be loaded")
    }
}
