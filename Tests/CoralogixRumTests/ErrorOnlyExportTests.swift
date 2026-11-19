//
//  ErrorOnlyExportTests.swift
//
//  End to end through `CoralogixExporter.export()`: what a session held until an error puts on the
//  wire, before and after its error, natively and through a hybrid `beforeSend` round trip, across
//  rotation, shutdown, and a crash recovered on the next launch.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class ErrorOnlyExportTests: XCTestCase {

    private var directory: URL!
    private var rum: CoralogixRum?
    /// The message each exported span stands for, by its span id: only logs carry a message on the wire.
    private var labels: [String: String] = [:]
    private let labelsLock = NSLock()

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ErrorOnlyExport-\(UUID().uuidString)")
        ErrorOnlyBuffer.testDirectory = directory
    }

    override func tearDown() {
        rum?.shutdown()
        rum = nil
        ErrorOnlyBuffer.testDirectory = nil
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Holding and the trigger

    func testSampledOut_flag_holdsEverything_thenAnErrorSendsItAllWithTheFields() throws {
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true))

        export(exporter, .log, message: "held-log")
        export(exporter, .navigation, message: "held-nav")
        XCTAssertTrue(payloads(uploader, withMessages: ["held-log", "held-nav"]).isEmpty, "Held until an error.")

        export(exporter, .error, severity: .error, message: "the-error")
        exporter.errorOnlyDrain.waitUntilSettled()

        let error = try XCTUnwrap(payload(uploader, message: "the-error"))
        XCTAssertEqual(session(error)[Keys.onlyWithErrorMode.rawValue] as? Bool, true)
        XCTAssertEqual(session(error)[Keys.hasError.rawValue] as? Bool, true, "The trigger carries hasError.")
        let snapshot = try XCTUnwrap(error[Keys.snapshotContext.rawValue] as? [String: Any])
        XCTAssertGreaterThan(snapshot[Keys.errorCount.rawValue] as? Int ?? 0, 0, "The grid needs errorCount > 0.")

        let held = payloads(uploader, withMessages: ["held-log", "held-nav"])
        XCTAssertEqual(held.compactMap(message), ["held-log", "held-nav"], "Drained oldest first.")
        for event in held {
            XCTAssertEqual(session(event)[Keys.onlyWithErrorMode.rawValue] as? Bool, true)
            XCTAssertNil(session(event)[Keys.hasError.rawValue], "Events before the error do not carry hasError.")
        }

        export(exporter, .log, message: "after")
        XCTAssertEqual(session(try XCTUnwrap(payload(uploader, message: "after")))[Keys.hasError.rawValue] as? Bool, true,
                       "After the error the session reports live, with hasError.")
    }

    func testSampledOut_flag_noError_sendsNothing() throws {
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true))
        export(exporter, .log, message: "held")
        export(exporter, .error, severity: .critical, message: "critical")
        exporter.errorOnlyDrain.waitUntilSettled()
        XCTAssertTrue(uploader.uploadedSpans.isEmpty, "Critical is not error: nothing is sent.")
    }

    func testSampledIn_flagOn_sendsAtOnce_withModeFalse() throws {
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 100, alwaysTrack: true))
        export(exporter, .log, message: "live")
        let event = try XCTUnwrap(payload(uploader, message: "live"))
        XCTAssertEqual(session(event)[Keys.onlyWithErrorMode.rawValue] as? Bool, false)
        XCTAssertNil(session(event)[Keys.hasError.rawValue])
    }

    func testEnable_atRate100_holdsUntilAnError() throws {
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 100, config: SessionWithErrorConfig(enable: true)))
        export(exporter, .log, message: "held")
        XCTAssertNil(payload(uploader, message: "held"))
        export(exporter, .error, severity: .error, message: "boom")
        exporter.errorOnlyDrain.waitUntilSettled()
        XCTAssertNotNil(payload(uploader, message: "held"))
    }

    func testExcludedTypes_areHeldToo_thenSentWithTheError() throws {
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true, exclude: [.errors, .logs]))
        export(exporter, .log, message: "excluded-log")
        XCTAssertNil(payload(uploader, message: "excluded-log"), "Once error-only, excluded types are held as well.")
        export(exporter, .error, severity: .error, message: "boom")
        exporter.errorOnlyDrain.waitUntilSettled()
        XCTAssertNotNil(payload(uploader, message: "excluded-log"))
    }

    func testInstrumentationsToSend_areSentBeforeAnError_otherTypesWait() throws {
        let config = SessionWithErrorConfig(instrumentationsToSend: [.mobileVitals])
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true, config: config))
        export(exporter, .mobileVitals, message: "vitals")
        export(exporter, .log, message: "log")
        XCTAssertEqual(uploader.cxRumPayloads().compactMap(eventType), [CoralogixEventType.mobileVitals.rawValue])
    }

    func testTrigger_networkErrorYes_ignoredErrorNo() throws {
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true, ignoreErrors: ["ignored"]))
        export(exporter, .log, message: "held")
        export(exporter, .error, severity: .error, message: "ignored", errorMessage: "ignored")
        exporter.errorOnlyDrain.waitUntilSettled()
        XCTAssertTrue(uploader.uploadedSpans.isEmpty, "An error dropped by ignoreErrors does not trigger.")

        export(exporter, .networkRequest, severity: .error, message: "http-500")
        exporter.errorOnlyDrain.waitUntilSettled()
        XCTAssertNotNil(payload(uploader, message: "held"), "A network error triggers.")
    }

    func testTrigger_isDecidedAfterBeforeSend() throws {
        let options = makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true, beforeSend: { cxRum in
            var edited = cxRum
            guard var context = edited[Keys.eventContext.rawValue] as? [String: Any] else { return cxRum }
            let message = (edited[Keys.logContext.rawValue] as? [String: Any])?[Keys.message.rawValue] as? String
            if message == "demoted" { context[Keys.severity.rawValue] = CoralogixLogSeverity.info.rawValue }
            if message == "promoted" { context[Keys.severity.rawValue] = CoralogixLogSeverity.error.rawValue }
            edited[Keys.eventContext.rawValue] = context
            return edited
        })
        let (exporter, uploader) = try start(options)
        export(exporter, .log, severity: .error, message: "demoted")
        exporter.errorOnlyDrain.waitUntilSettled()
        XCTAssertTrue(uploader.uploadedSpans.isEmpty, "beforeSend cancelled the trigger.")

        export(exporter, .log, severity: .info, message: "promoted")
        exporter.errorOnlyDrain.waitUntilSettled()
        XCTAssertNotNil(payload(uploader, message: "promoted"), "beforeSend caused the trigger.")
        XCTAssertNotNil(payload(uploader, message: "demoted"), "And the demoted event was held and drained.")
    }

    // MARK: - Rotation and shutdown

    func testLateErrorWithinTheGrace_triggersTheEndedSession_andSendsWhatItHeld() throws {
        let clock = ManualDeliveryClock()
        ErrorOnlyBuffer.testClock = clock
        defer { ErrorOnlyBuffer.testClock = nil }
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true))
        let oldStamp = exporter.getSessionManager().sessionSpanAttributes()
        export(exporter, .log, message: "old-held")

        // reportError then createNewSession: the error is exported after the rotation.
        rum?.createNewSession()
        clock.advance(to: clock.now().addingTimeInterval(20))
        export(exporter, .error, severity: .error, message: "old-late-error", stamp: oldStamp)
        exporter.errorOnlyDrain.waitUntilSettled()

        XCTAssertNotNil(payload(uploader, message: "old-late-error"))
        XCTAssertNotNil(payload(uploader, message: "old-held"), "What the ended session held is sent with its error.")
        let oldId = oldStamp.first { $0.key == Keys.sessionId.rawValue }?.value
        XCTAssertEqual(session(try XCTUnwrap(payload(uploader, message: "old-held")))[Keys.sessionId.rawValue] as? String, oldId)
    }

    func testRotation_dropsWhatTheEndedSessionHeld_andNeverSendsItUnderTheNewOne() throws {
        let clock = ManualDeliveryClock()
        ErrorOnlyBuffer.testClock = clock
        defer { ErrorOnlyBuffer.testClock = nil }
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true))
        let sessionManager = exporter.getSessionManager()
        let oldStamp = sessionManager.sessionSpanAttributes()
        export(exporter, .log, message: "old-held")

        rum?.createNewSession()
        clock.advance(to: clock.now().addingTimeInterval(ErrorOnlyBuffer.endedSessionGrace + 1))
        // A late event of the ended session, exported after its grace.
        export(exporter, .error, severity: .error, message: "old-late-error", stamp: oldStamp)
        export(exporter, .log, message: "new-held")
        export(exporter, .error, severity: .error, message: "new-error")
        exporter.errorOnlyDrain.waitUntilSettled()

        XCTAssertNil(payload(uploader, message: "old-held"))
        XCTAssertNil(payload(uploader, message: "old-late-error"), "Past the grace, a late error cannot trigger the ended session.")
        XCTAssertNotNil(payload(uploader, message: "new-held"))
        let newId = try XCTUnwrap(sessionManager.currentSessionId)
        XCTAssertTrue(uploader.cxRumPayloads().allSatisfy { session($0)[Keys.sessionId.rawValue] as? String == newId })
    }

    func testShutdown_deletesTheBuffer() throws {
        let (exporter, _) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true))
        export(exporter, .log, message: "held")
        XCTAssertFalse(try files().isEmpty, "Precondition: the event is on disk.")
        rum?.shutdown()
        XCTAssertTrue(try files().isEmpty, "Nothing held leaks into a later init.")
    }

    // MARK: - Hybrid

    func testHybrid_decidesAfterTheJSBeforeSend_andRestoresTheMode() throws {
        var options = makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true)
        let js = HandedToJS()
        options.beforeSendCallBack = { js.append($0) }
        let rum = CoralogixRum(options: options, sdkFramework: .flutter(version: "1.0.0"))
        self.rum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = CapturingSpanUploader()
        exporter.spanUploader = uploader

        export(exporter, .log, message: "js-held")
        XCTAssertTrue(uploader.uploadedSpans.isEmpty, "Nothing is uploaded before JS answers.")
        let forged = js.events.filter { message(cxRum($0)) == "js-held" }.map { event -> [String: Any] in
            var cxRum = self.cxRum(event)
            var session = cxRum[Keys.sessionContext.rawValue] as? [String: Any] ?? [:]
            session[Keys.onlyWithErrorMode.rawValue] = false
            session[Keys.hasError.rawValue] = true
            cxRum[Keys.sessionContext.rawValue] = session
            var result = event
            result[Keys.text.rawValue] = [Keys.cxRum.rawValue: cxRum]
            return result
        }
        exporter.sendBeforeSendData(data: forged)
        XCTAssertTrue(uploader.uploadedSpans.isEmpty, "The mode is restored on return, so the event is still held.")

        export(exporter, .error, severity: .error, message: "js-error")
        exporter.sendBeforeSendData(data: js.events.filter { message(cxRum($0)) == "js-error" })
        exporter.errorOnlyDrain.waitUntilSettled()
        let held = try XCTUnwrap(payload(uploader, message: "js-held"))
        XCTAssertEqual(session(held)[Keys.onlyWithErrorMode.rawValue] as? Bool, true)
        XCTAssertNil(session(held)[Keys.hasError.rawValue], "A forged hasError does not survive.")
    }

    func testHybrid_featureOff_bothFieldsAreRestoredOnReturn() throws {
        var options = makeErrorOnlyOptions(sampleRate: 100)
        let js = HandedToJS()
        options.beforeSendCallBack = { js.append($0) }
        let rum = CoralogixRum(options: options, sdkFramework: .reactNative(version: "1.0.0"))
        self.rum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = CapturingSpanUploader()
        exporter.spanUploader = uploader

        export(exporter, .log, message: "full")
        exporter.sendBeforeSendData(data: forging(js.events.filter { message(cxRum($0)) == "full" },
                                                  onlyWithErrorMode: true))

        let sent = try XCTUnwrap(payload(uploader, message: "full"))
        XCTAssertEqual(session(sent)[Keys.onlyWithErrorMode.rawValue] as? Bool, false,
                       "A callback cannot mark a full session error-only.")
        XCTAssertNil(session(sent)[Keys.hasError.rawValue], "Nor give it hasError.")
    }

    func testHybrid_aReturnedEventKeepsItsOwnMode_evenUnderAnUnknownSession() throws {
        var options = makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true)
        let js = HandedToJS()
        options.beforeSendCallBack = { js.append($0) }
        let rum = CoralogixRum(options: options, sdkFramework: .flutter(version: "1.0.0"))
        self.rum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = CapturingSpanUploader()
        exporter.spanUploader = uploader

        export(exporter, .log, message: "held")
        let returned = forging(js.events.filter { message(cxRum($0)) == "held" }, onlyWithErrorMode: false,
                               sessionId: "a-session-the-sdk-does-not-know")
        exporter.sendBeforeSendData(data: returned)
        XCTAssertNil(payload(uploader, message: "held"),
                     "The event was handed out error-only; it is never sent live as a full session's.")
    }

    // MARK: - Crash on the next launch

    func testRecoveredCrash_sendsTheCrash_thenWhatItsSessionHeld() throws {
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true))
        // The launch that crashed held two events of session "crashed".
        let earlier = ErrorOnlyBuffer(maxRumEvents: 5_000, directory: directory)
        for text in ["before-1", "before-2"] {
            let event: [String: Any] = [Keys.text.rawValue: [Keys.cxRum.rawValue: [Keys.logContext.rawValue: [Keys.message.rawValue: text]]]]
            earlier.hold(try JSONSerialization.data(withJSONObject: event), sessionId: "crashed")
        }

        exporter.recoverErrorOnlyLeftovers(crashedSessionIds: ["crashed"])
        XCTAssertTrue(uploader.uploadedSpans.isEmpty, "Kept for the crash, not sent before it.")

        _ = exporter.export(spans: [makeCrashSpan(sessionId: "crashed")], explicitTimeout: nil)
        exporter.waitForStoredCrashUploads()
        exporter.errorOnlyDrain.waitUntilSettled()

        XCTAssertEqual(uploader.cxRumPayloads().map(message), ["the-crash", "before-1", "before-2"],
                       "The crash first, then the drain.")
        let crash = try XCTUnwrap(uploader.cxRumPayloads().first)
        XCTAssertEqual(session(crash)[Keys.hasError.rawValue] as? Bool, true)
    }

    func testLeftoverWithoutCrashOrError_isDeletedAtLaunch() throws {
        let (exporter, uploader) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true))
        let earlier = ErrorOnlyBuffer(maxRumEvents: 5_000, directory: directory)
        earlier.hold(Data("{}".utf8), sessionId: "ended-clean")
        exporter.recoverErrorOnlyLeftovers(crashedSessionIds: [])
        exporter.errorOnlyDrain.waitUntilSettled()
        XCTAssertTrue(uploader.uploadedSpans.isEmpty)
        XCTAssertFalse(try files().contains { $0.hasPrefix("ended-clean") }, "Deleted unsent.")
    }

    // MARK: - tracesExporter

    func testTracesExporter_seesOnlyWhatIsSent() throws {
        let capture = EventTypeCapture()
        let (exporter, _) = try start(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true,
                                                         tracesExporter: capture.tracesExporterCallback()))
        export(exporter, .log, message: "held")
        XCTAssertFalse(capture.eventTypes.contains(CoralogixEventType.log.rawValue), "A held event is not forwarded.")
        export(exporter, .error, severity: .error, message: "boom")
        XCTAssertTrue(capture.eventTypes.contains(CoralogixEventType.error.rawValue), "The sent trigger is forwarded.")
    }

    // MARK: - Helpers

    /// What a hybrid callback hands back after rewriting the read-only session fields.
    private func forging(_ events: [[String: Any]], onlyWithErrorMode: Bool, sessionId: String? = nil) -> [[String: Any]] {
        events.map { event in
            CoralogixExporter.updatingSessionContext(of: event) { session in
                session[Keys.onlyWithErrorMode.rawValue] = onlyWithErrorMode
                session[Keys.hasError.rawValue] = true
                if let sessionId { session[Keys.sessionId.rawValue] = sessionId }
            }
        }
    }

    private func start(_ options: CoralogixExporterOptions) throws -> (CoralogixExporter, CapturingSpanUploader) {
        let rum = CoralogixRum(options: options)
        self.rum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = CapturingSpanUploader()
        exporter.spanUploader = uploader
        return (exporter, uploader)
    }

    /// Exports one log-shaped event stamped with the live session (or `stamp`).
    private func export(_ exporter: CoralogixExporter,
                        _ type: CoralogixEventType,
                        severity: CoralogixLogSeverity = .info,
                        message: String,
                        errorMessage: String? = nil,
                        stamp: [(key: String, value: String)]? = nil) {
        var extra: [String: AttributeValue] = [Keys.severity.rawValue: .string(String(severity.rawValue)),
                                               Keys.message.rawValue: .string(message)]
        for (key, value) in stamp ?? exporter.getSessionManager().sessionSpanAttributes() {
            extra[key] = .string(value)
        }
        if let errorMessage { extra[Keys.errorMessage.rawValue] = .string(errorMessage) }
        let span = makeSamplingSpan(eventType: type, extraAttributes: extra)
        label(span, message)
        _ = exporter.export(spans: [span], explicitTimeout: nil)
    }

    private func label(_ span: SpanData, _ text: String) {
        labelsLock.lock(); defer { labelsLock.unlock() }
        labels[span.spanId.hexString] = text
    }

    private func makeCrashSpan(sessionId: String) -> SpanData {
        let attributes: [String: AttributeValue] = [
            Keys.eventType.rawValue: .string(CoralogixEventType.error.rawValue),
            Keys.severity.rawValue: .string("5"),
            Keys.source.rawValue: .string("console"),
            Keys.environment.rawValue: .string("test"),
            Keys.sessionId.rawValue: .string(sessionId),
            Keys.sessionCreationDate.rawValue: .string("1609459200"),
            Keys.spanSessionSampledIn.rawValue: .string("false"),
            Keys.spanSessionOnlyWithErrorMode.rawValue: .string("true"),
            Keys.errorMessage.rawValue: .string("the-crash"),
            Keys.isCrash.rawValue: .bool(true),
            Keys.crashEventId.rawValue: .string(UUID().uuidString)
        ]
        let span = SpanData(traceId: TraceId.random(), spanId: SpanId.random(), name: "crash", kind: .client,
                            startTime: Date(), attributes: attributes, endTime: Date(), hasEnded: true)
        label(span, "the-crash")
        return span
    }

    private func files() throws -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    private func cxRum(_ event: [String: Any]) -> [String: Any] {
        CoralogixExporter.cxRum(of: event) ?? [:]
    }

    private func session(_ cxRum: [String: Any]) -> [String: Any] {
        cxRum[Keys.sessionContext.rawValue] as? [String: Any] ?? [:]
    }

    private func message(_ cxRum: [String: Any]) -> String? {
        labelsLock.lock(); defer { labelsLock.unlock() }
        if let spanId = cxRum[Keys.spanId.rawValue] as? String, let text = labels[spanId] { return text }
        return (cxRum[Keys.logContext.rawValue] as? [String: Any])?[Keys.message.rawValue] as? String
    }

    private func eventType(_ cxRum: [String: Any]) -> String? {
        (cxRum[Keys.eventContext.rawValue] as? [String: Any])?[Keys.type.rawValue] as? String
    }

    private func payload(_ uploader: CapturingSpanUploader, message text: String) -> [String: Any]? {
        uploader.cxRumPayloads().first { message($0) == text }
    }

    private func payloads(_ uploader: CapturingSpanUploader, withMessages texts: Set<String>) -> [[String: Any]] {
        uploader.cxRumPayloads().filter { message($0).map(texts.contains) ?? false }
    }
}

private final class HandedToJS {
    private let lock = NSLock()
    private var _events: [[String: Any]] = []

    var events: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    func append(_ batch: [[String: Any]]) {
        lock.lock(); defer { lock.unlock() }
        _events += batch
    }
}
