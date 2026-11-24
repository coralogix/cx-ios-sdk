//
//  ReplayMessagesTests.swift
//
//  How RUM reacts to what the session-replay wrapper tells it over the RUM bus (recording state,
//  screenshots, replay settings), the shared mask tag resolved by name, and the internal header
//  that keeps replay's own uploads out of network instrumentation.
//
//  SANCTIONED SYMBOLS (the implementation may create exactly these; the tests use nothing else new):
//
//    UIView.cxMask becomes `@objc` — same Swift signature, same storage (one associated object),
//        so `value(forKey: "cxMask")`, `setValue(_:forKey: "cxMask")`,
//        `responds(to: NSSelectorFromString("cxMask"))` and `"setCxMask:"` reach it.
//    `ScreenshotContext.page` is removed (property and wire key). These tests write the stored
//        attribute as the literal "page", so `Keys.page` may go too.
//    Anything internal the coder needs to route the messages (a handler installed with the existing
//    `RumBus.setRumHandler(_:)`, a per-session recording memory, an internal-event name/data
//    attribute on the span). No new test seam: the tests drive `CoralogixRum.publish(_:)`,
//    `CoralogixRum.drainBus()`, `CoralogixExporter.export(spans:explicitTimeout:)`, `flush()`,
//    `setNetworkRequestContext(dictionary:)` and `URLSession`.
//
//  WIRE SHAPES these tests pin:
//    screenshot event: `event_context.type == "screenshot"`, `screenshot_context.screenshotId` is the
//        message's id, `screenshot_context.segmentTimestamp` and `cx_rum.timestamp` are the message's
//        `timestamp` (epoch ms), no `page` key; `session_context.sessionId` is RUM's current session,
//        `view_context.view` its current view.
//    replay settings: `event_context.type == "internal"`, `internal_context.event == "replay_settings"`,
//        `internal_context.data` is the flat settings map (string -> String, number -> Double,
//        bool -> Bool, null -> NSNull). The startup event keeps `internal_context.event == "init"`.
//    hasRecording: `session_context.hasRecording`, read against the event's own session id.
//    internal header: `X-Coralogix-Internal: 1`, name matched case-insensitively.
//
//  Every test is marked RED-now (fails until implemented) or GUARD (must stay true).
//

import XCTest
#if canImport(UIKit)
import UIKit
#endif
@_spi(RumBus) @testable import Coralogix

final class ReplayMessagesTests: XCTestCase {

    private var rums: [CoralogixRum] = []
    private var subscriptions: [RumBusSubscription] = []

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
        // The bus is process-wide: leave it with no sticky state and no RUM handler.
        CoralogixRum(options: Self.options()).shutdown()
        CoralogixRum.drainBus()
    }

    override func tearDown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        rums.forEach { $0.shutdown() }
        rums = []
        CoralogixRum.drainBus()
        CoralogixRum.isInitialized = false
        super.tearDown()
    }

    // MARK: - Before init / after shutdown / live instance

    /// RED-now. A screenshot published before RUM starts is dropped, not replayed at init; one after init is handled.
    func testScreenshotBeforeInit_isDropped_afterInit_isHandled() throws {
        let sm = Self.sessionManager()
        let sessionId = try XCTUnwrap(sm.currentSessionId)
        CoralogixRum.publish(.screenshotTaken(screenshotId: "before-init", sessionId: sessionId, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()

        let (rum, uploader) = try start(sm: sm)
        CoralogixRum.publish(.screenshotTaken(screenshotId: "after-init", sessionId: sessionId, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()

        _ = try awaitEvent(rum, uploader, "screenshot after init") { Self.screenshotId(of: $0) == "after-init" }
        XCTAssertTrue(screenshots(uploader).filter { Self.screenshotId(of: $0) == "before-init" }.isEmpty,
                      "a message published before init was handled")
    }

    /// RED-now. RecordingStarted before init leaves no trace once RUM starts on that session.
    func testRecordingStartedBeforeInit_isDropped() throws {
        let sm = Self.sessionManager()
        let sessionId = try XCTUnwrap(sm.currentSessionId)
        CoralogixRum.publish(.recordingStarted(sessionId: sessionId))
        CoralogixRum.drainBus()

        let (rum, uploader) = try start(sm: sm)
        XCTAssertEqual(try exportedHasRecording(sessionId, rum, uploader), false, "published before init")

        // Non-vacuous: the same message after init is handled.
        CoralogixRum.publish(.recordingStarted(sessionId: sessionId))
        CoralogixRum.drainBus()
        XCTAssertEqual(try exportedHasRecording(sessionId, rum, uploader), true)
    }

    /// RED-now. A screenshot published after shutdown is dropped: a later init on the same session never reports it.
    func testScreenshotAfterShutdown_isDropped() throws {
        let sm = Self.sessionManager()
        let sessionId = try XCTUnwrap(sm.currentSessionId)
        let first = CoralogixRum(options: Self.options(), sessionManager: sm)
        first.shutdown()
        CoralogixRum.publish(.screenshotTaken(screenshotId: "after-shutdown", sessionId: sessionId, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()

        let (rum, uploader) = try start(sm: sm)
        CoralogixRum.publish(.screenshotTaken(screenshotId: "after-reinit", sessionId: sessionId, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()

        _ = try awaitEvent(rum, uploader, "screenshot after re-init") { Self.screenshotId(of: $0) == "after-reinit" }
        XCTAssertTrue(screenshots(uploader).filter { Self.screenshotId(of: $0) == "after-shutdown" }.isEmpty,
                      "a message published after shutdown was handled")
    }

    /// RED-now. With an older instance never shut down, only the live (newest) instance handles: one event, not two.
    func testOnlyTheLiveInstanceHandles() throws {
        let (older, olderUploader) = try start()
        let (newer, newerUploader) = try start()
        let sessionId = try XCTUnwrap(newer.sessionManager?.currentSessionId)

        CoralogixRum.publish(.screenshotTaken(screenshotId: "live-only", sessionId: sessionId, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()

        _ = try awaitEvent(newer, newerUploader, "screenshot") { Self.screenshotId(of: $0) == "live-only" }
        older.flush()
        newer.flush()
        let all = screenshots(olderUploader) + screenshots(newerUploader)
        XCTAssertEqual(all.filter { Self.screenshotId(of: $0) == "live-only" }.count, 1, "handled by more than one instance")
    }

    // MARK: - hasRecording

    /// RED-now. RecordingStarted for the current session: RUM's next event carries hasRecording true.
    func testRecordingStarted_nextEventCarriesHasRecording() throws {
        let (rum, uploader) = try start()
        let sessionId = try XCTUnwrap(rum.sessionManager?.currentSessionId)
        XCTAssertEqual(try exportedHasRecording(sessionId, rum, uploader), false, "fixture: nothing recorded yet")

        CoralogixRum.publish(.recordingStarted(sessionId: sessionId))
        CoralogixRum.drainBus()

        rum.log(severity: .info, message: "after-recording-started")
        let log = try awaitEvent(rum, uploader, "log") { Self.logMessage(of: $0) == "after-recording-started" }
        XCTAssertEqual(Self.sessionId(of: log), sessionId)
        XCTAssertEqual(Self.hasRecording(of: log), true)
    }

    /// RED-now. RecordingStopped ends the recording but never clears the flag.
    func testRecordingStopped_doesNotClearHasRecording() throws {
        let (rum, uploader) = try start()
        let sessionId = try XCTUnwrap(rum.sessionManager?.currentSessionId)

        CoralogixRum.publish(.recordingStarted(sessionId: sessionId))
        CoralogixRum.publish(.recordingStopped(sessionId: sessionId))
        CoralogixRum.drainBus()

        XCTAssertEqual(try exportedHasRecording(sessionId, rum, uploader), true)
    }

    /// GUARD. A RecordingStarted naming a session that is not RUM's current one is ignored.
    func testRecordingStarted_foreignSession_isIgnored() throws {
        let (rum, uploader) = try start()
        let sessionId = try XCTUnwrap(rum.sessionManager?.currentSessionId)

        CoralogixRum.publish(.recordingStarted(sessionId: "not-a-rum-session"))
        CoralogixRum.drainBus()

        XCTAssertEqual(try exportedHasRecording(sessionId, rum, uploader), false)
        XCTAssertEqual(try exportedHasRecording("not-a-rum-session", rum, uploader), false)
    }

    /// RED-now. A RecordingStarted for the previous session arriving after rotation is ignored at receipt.
    func testRecordingStarted_forThePreviousSessionAfterRotation_isIgnored() throws {
        let (rum, uploader) = try start()
        let first = try XCTUnwrap(rum.sessionManager?.currentSessionId)
        rum.createNewSession()
        let second = try XCTUnwrap(rum.sessionManager?.currentSessionId)
        XCTAssertNotEqual(first, second, "fixture: rotated")

        CoralogixRum.publish(.recordingStarted(sessionId: first))
        CoralogixRum.drainBus()

        XCTAssertEqual(try exportedHasRecording(first, rum, uploader), false, "the old session was not current at receipt")
        XCTAssertEqual(try exportedHasRecording(second, rum, uploader), false)
        // Non-vacuous: the current session's message is handled.
        CoralogixRum.publish(.recordingStarted(sessionId: second))
        CoralogixRum.drainBus()
        XCTAssertEqual(try exportedHasRecording(second, rum, uploader), true)
    }

    /// RED-now. After rotation a late event of the recorded session still carries true; the new session's carries false.
    func testRotation_previousSessionKeepsItsFlag_newSessionStartsFalse() throws {
        let (rum, uploader) = try start()
        let first = try XCTUnwrap(rum.sessionManager?.currentSessionId)
        CoralogixRum.publish(.recordingStarted(sessionId: first))
        CoralogixRum.drainBus()

        rum.createNewSession()
        let second = try XCTUnwrap(rum.sessionManager?.currentSessionId)
        XCTAssertNotEqual(first, second, "fixture: rotated")

        XCTAssertEqual(try exportedHasRecording(first, rum, uploader), true, "a late event of the recorded session")
        XCTAssertEqual(try exportedHasRecording(second, rum, uploader), false, "the new session has not recorded")
    }

    /// RED-now. RUM remembers the latest two recorded sessions: a third evicts the oldest.
    func testThirdRecordedSession_evictsTheOldest() throws {
        let (rum, uploader) = try start()
        var ids: [String] = []
        for index in 0..<3 {
            if index > 0 { rum.createNewSession() }
            let id = try XCTUnwrap(rum.sessionManager?.currentSessionId)
            ids.append(id)
            CoralogixRum.publish(.recordingStarted(sessionId: id))
            CoralogixRum.drainBus()
        }
        XCTAssertEqual(Set(ids).count, 3, "fixture: three sessions")

        XCTAssertEqual(try exportedHasRecording(ids[0], rum, uploader), false, "the oldest is forgotten")
        XCTAssertEqual(try exportedHasRecording(ids[1], rum, uploader), true, "the previous session is remembered")
        XCTAssertEqual(try exportedHasRecording(ids[2], rum, uploader), true, "the current session")
    }

    /// RED-now. Re-init clears the memory: an event naming the recorded session reports false afterwards.
    func testReinit_clearsTheRecordingMemory() throws {
        let (first, firstUploader) = try start()
        let sessionId = try XCTUnwrap(first.sessionManager?.currentSessionId)
        CoralogixRum.publish(.recordingStarted(sessionId: sessionId))
        CoralogixRum.drainBus()
        XCTAssertEqual(try exportedHasRecording(sessionId, first, firstUploader), true, "fixture: recorded")
        first.shutdown()

        let (second, secondUploader) = try start()
        XCTAssertEqual(try exportedHasRecording(sessionId, second, secondUploader), false)
    }

    /// RED-now. The session snapshot reports the recording too (an error always carries a snapshot).
    func testSnapshot_reportsHasRecording() throws {
        let (rum, uploader) = try start()
        let sessionId = try XCTUnwrap(rum.sessionManager?.currentSessionId)
        CoralogixRum.publish(.recordingStarted(sessionId: sessionId))
        CoralogixRum.drainBus()

        rum.reportError(message: "snapshot-after-recording") // an error-severity log
        let error = try awaitEvent(rum, uploader, "error log") { Self.logMessage(of: $0) == "snapshot-after-recording" }
        let snapshot = try XCTUnwrap(error[Keys.snapshotContext.rawValue] as? [String: Any], "an error carries a snapshot")
        XCTAssertEqual(snapshot[Keys.hasRecording.rawValue] as? Bool, true)
    }

    // MARK: - ScreenshotTaken

    /// RED-now. One screenshot event: the message's id and time, RUM's session and view, no page.
    func testScreenshotTaken_exportsOneScreenshotEvent() throws {
        let sm = Self.sessionManager()
        Self.backdate(sm, seconds: 30)
        let (rum, uploader) = try start(sm: sm)
        let sessionId = try XCTUnwrap(sm.currentSessionId)
        rum.setView(name: "Checkout")
        let timestamp = Self.nowMs() - 5_000 // distinct from the handling time

        CoralogixRum.publish(.screenshotTaken(screenshotId: "shot-1", sessionId: sessionId, timestamp: timestamp))
        CoralogixRum.drainBus()

        let event = try awaitEvent(rum, uploader, "screenshot") { Self.screenshotId(of: $0) == "shot-1" }
        XCTAssertEqual(Self.type(of: event), "screenshot")
        XCTAssertEqual(Self.sessionId(of: event), sessionId)
        XCTAssertEqual((event[Keys.viewContext.rawValue] as? [String: Any])?[Keys.view.rawValue] as? String, "Checkout")
        let eventTime = try XCTUnwrap(event[Keys.timestamp.rawValue] as? Int)
        XCTAssertEqual(Double(eventTime), Double(timestamp), accuracy: 1, "the message's timestamp is the event time")
        let context = try XCTUnwrap(event[Keys.screenshotContext.rawValue] as? [String: Any])
        let segment = try XCTUnwrap(context[Keys.segmentTimestamp.rawValue] as? Int)
        XCTAssertEqual(Double(segment), Double(timestamp), accuracy: 1)
        XCTAssertNil(context["page"], "no page is sent")

        rum.flush()
        XCTAssertEqual(screenshots(uploader).filter { Self.screenshotId(of: $0) == "shot-1" }.count, 1, "exactly one")
    }

    /// RED-now. A sessionId that is not RUM's current session (unknown, or the previous one) exports nothing.
    func testScreenshotTaken_notTheCurrentSession_exportsNothing() throws {
        let (rum, uploader) = try start()
        let first = try XCTUnwrap(rum.sessionManager?.currentSessionId)
        rum.createNewSession()
        let second = try XCTUnwrap(rum.sessionManager?.currentSessionId)

        CoralogixRum.publish(.screenshotTaken(screenshotId: "foreign", sessionId: "not-a-rum-session", timestamp: Self.nowMs()))
        CoralogixRum.publish(.screenshotTaken(screenshotId: "previous", sessionId: first, timestamp: Self.nowMs()))
        CoralogixRum.publish(.screenshotTaken(screenshotId: "current", sessionId: second, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()

        _ = try awaitEvent(rum, uploader, "current screenshot") { Self.screenshotId(of: $0) == "current" }
        let ids = screenshots(uploader).compactMap(Self.screenshotId(of:))
        XCTAssertFalse(ids.contains("foreign"), "\(ids)")
        XCTAssertFalse(ids.contains("previous"), "\(ids)")
    }

    /// RED-now. The check uses RUM's own session state, which rotates past max age: the expired session's id exports nothing.
    func testScreenshotTaken_forASessionPastMaxAge_exportsNothing() throws {
        let sm = Self.sessionManager()
        let (rum, uploader) = try start(sm: sm)
        let expired = try XCTUnwrap(sm.currentSessionId)
        Self.backdate(sm, seconds: 3601)

        CoralogixRum.publish(.screenshotTaken(screenshotId: "expired", sessionId: expired, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()
        let current = try XCTUnwrap(rum.getSessionId, "RUM's own read rotates")
        XCTAssertNotEqual(current, expired, "fixture: rotated past max age")
        CoralogixRum.publish(.screenshotTaken(screenshotId: "fresh", sessionId: current, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()

        let fresh = try awaitEvent(rum, uploader, "fresh screenshot") { Self.screenshotId(of: $0) == "fresh" }
        XCTAssertEqual(Self.sessionId(of: fresh), current)
        XCTAssertFalse(screenshots(uploader).contains { Self.screenshotId(of: $0) == "expired" })
    }

    /// RED-now. The screenshot event goes through the normal pipeline: beforeSend sees it.
    func testScreenshotTaken_beforeSendSeesIt() throws {
        let seen = Seen()
        var options = Self.options()
        options.beforeSend = { cxRum in seen.add(cxRum); return cxRum }
        let (rum, uploader) = try start(options)
        let sessionId = try XCTUnwrap(rum.sessionManager?.currentSessionId)

        CoralogixRum.publish(.screenshotTaken(screenshotId: "seen", sessionId: sessionId, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()

        _ = try awaitEvent(rum, uploader, "screenshot") { Self.screenshotId(of: $0) == "seen" }
        XCTAssertTrue(seen.all.contains { Self.screenshotId(of: $0) == "seen" }, "beforeSend did not see the screenshot")
    }

    /// GUARD. Sampling applies: in a sampled-out session (logs excluded from sampling) the log goes, the screenshot does not.
    func testScreenshotTaken_sampledOutSession_isNotExported() throws {
        let (rum, uploader) = try start(makeSamplingOptions(sampleRate: 0, exclude: [.logs]))
        let sessionId = try XCTUnwrap(rum.sessionManager?.currentSessionId)
        XCTAssertEqual(rum.sessionManager?.isSessionSampledIn, false, "fixture: sampled out")

        CoralogixRum.publish(.screenshotTaken(screenshotId: "sampled-out", sessionId: sessionId, timestamp: Self.nowMs()))
        CoralogixRum.drainBus()
        rum.log(severity: .info, message: "marker-after-screenshot")

        _ = try awaitEvent(rum, uploader, "marker log") { Self.logMessage(of: $0) == "marker-after-screenshot" }
        XCTAssertFalse(screenshots(uploader).contains { Self.screenshotId(of: $0) == "sampled-out" })
    }

    /// RED-now. A stored span that still carries a page decodes, and the context sends no page.
    func testScreenshotContext_storedPage_isIgnored() {
        let span = MockSpanData(attributes: [Keys.screenshotId.rawValue: AttributeValue("stored"),
                                             "page": AttributeValue("4")],
                                startTime: Date(timeIntervalSince1970: 1_700_000_000))
        let context = ScreenshotContext(otel: span)
        XCTAssertTrue(context.isValid())
        let dict = context.getDictionary()
        XCTAssertEqual(dict[Keys.screenshotId.rawValue] as? String, "stored")
        XCTAssertNil(dict["page"])
    }

    // MARK: - ReplaySettings

    /// RED-now. ReplaySettings is one internal event `replay_settings` carrying the flat settings; beforeSend sees it
    /// as it sees the init event.
    func testReplaySettings_exportsOneInternalEvent_seenByBeforeSend() throws {
        let seen = Seen()
        var options = Self.options()
        options.beforeSend = { cxRum in seen.add(cxRum); return cxRum }
        let (rum, uploader) = try start(options)

        CoralogixRum.publish(.replaySettings(settings: ["mode": .string("full"), "rate": .number(0.5),
                                                       "maskAll": .bool(true), "unset": .null]))
        CoralogixRum.drainBus()

        let event = try awaitEvent(rum, uploader, "replay_settings") { Self.internalEventName(of: $0) == "replay_settings" }
        XCTAssertEqual(Self.type(of: event), CoralogixEventType.internalKey.rawValue)
        let internalContext = try XCTUnwrap(event[Keys.internalContext.rawValue] as? [String: Any])
        let data = try XCTUnwrap(internalContext[Keys.data.rawValue] as? [String: Any])
        XCTAssertEqual(data.count, 4, "\(data)")
        XCTAssertEqual(data["mode"] as? String, "full")
        XCTAssertEqual(data["rate"] as? Double, 0.5)
        XCTAssertEqual(data["maskAll"] as? Bool, true)
        XCTAssertTrue(data["unset"] is NSNull, "\(String(describing: data["unset"]))")

        rum.flush()
        XCTAssertEqual(uploader.cxRumPayloads().filter { Self.internalEventName(of: $0) == "replay_settings" }.count, 1)
        let seenNames = seen.all.compactMap(Self.internalEventName(of:))
        XCTAssertTrue(seenNames.contains("init"), "fixture: beforeSend sees the init event: \(seenNames)")
        XCTAssertTrue(seenNames.contains("replay_settings"), "\(seenNames)")
    }

    /// GUARD. The startup event is still `init` with the init data, not replaced by the settings path.
    func testInitEvent_keepsItsNameAndData() throws {
        let (rum, uploader) = try start()
        let event = try awaitEvent(rum, uploader, "init") { Self.internalEventName(of: $0) == "init" }
        let data = (event[Keys.internalContext.rawValue] as? [String: Any])?[Keys.data.rawValue] as? [String: Any]
        XCTAssertEqual(data?[Keys.application.rawValue] as? String, "TestApp")
    }

    // MARK: - Deadlock

    /// GUARD. Handling replay's messages while the app rotates sessions never deadlocks the bus.
    func testHandlingWhileRumRotates_doesNotDeadlock() throws {
        let (rum, _) = try start()
        let done = expectation(description: "rotations")
        DispatchQueue.global().async {
            for _ in 0..<50 { rum.createNewSession() }
            done.fulfill()
        }
        for index in 0..<50 {
            let id = rum.sessionManager?.currentSessionId ?? ""
            CoralogixRum.publish(.recordingStarted(sessionId: id))
            CoralogixRum.publish(.screenshotTaken(screenshotId: "spin-\(index)", sessionId: id, timestamp: Self.nowMs()))
        }
        wait(for: [done], timeout: 10)
        let drained = expectation(description: "bus drained")
        DispatchQueue.global().async {
            CoralogixRum.drainBus()
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10) // a deadlocked bus queue never drains
    }

    // MARK: - Mask tag

    /// RED-now. The tag RUM announces resolves by name to the same mark the property reads, both ways.
    func testMaskTag_resolvesByName_toTheCxMaskProperty() throws {
        let (_, _) = try start()
        let rec = Recorded()
        subscriptions.append(CoralogixRum.subscribe { rec.add($0) })
        CoralogixRum.drainBus()
        guard case let .currentState(_, _, _, _, _, tag)? = rec.messages.first else {
            return XCTFail("expected CurrentState, got \(rec.messages)")
        }
        XCTAssertEqual(tag, RumBus.maskTag)
        XCTAssertEqual(tag, "cxMask")

        let view = UIView()
        guard Self.resolvesByName(view, tag) else { return } // value(forKey:) on an unknown key raises
        XCTAssertEqual(view.value(forKey: tag) as? Bool, false)
        view.cxMask = true
        XCTAssertEqual(view.value(forKey: tag) as? Bool, true, "property -> name")

        let other = UIView()
        other.setValue(true, forKey: tag)
        XCTAssertTrue(other.cxMask, "name -> property")
        other.setValue(false, forKey: tag)
        XCTAssertFalse(other.cxMask)
    }

    /// RED-now. A mark set by name is inherited and drives tap masking and the mask geometry.
    func testMaskSetByName_isInheritedAndMasksTaps() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.isHidden = false
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let child = UILabel(frame: CGRect(x: 10, y: 10, width: 50, height: 20))
        child.text = "1234"
        parent.addSubview(child)
        window.addSubview(parent)
        guard Self.resolvesByName(parent, RumBus.maskTag) else { return }

        parent.setValue(true, forKey: RumBus.maskTag)

        XCTAssertTrue(child.isInsideMaskedSubtree)
        let tap = TapDataExtractor.extract(from: TouchEvent(view: child, location: .zero, eventType: .click, scrollDirection: nil))
        XCTAssertEqual(tap[Keys.isMaskedElement.rawValue] as? Bool, true)
        let rects = try XCTUnwrap(UIView.deliberateMaskRects(in: [window]))
        XCTAssertTrue(rects.contains { $0.contains(CGPoint(x: 50, y: 50)) }, "\(rects)")
    }

    /// GUARD. The property and SwiftUI-free path keep working as before (no name involved).
    func testCxMaskProperty_unchanged() {
        let parent = UIView()
        let child = UIView()
        parent.addSubview(child)
        XCTAssertFalse(child.isInsideMaskedSubtree)
        parent.cxMask = true
        XCTAssertTrue(parent.cxMask)
        XCTAssertTrue(child.isInsideMaskedSubtree)
    }

    // MARK: - Helpers

    private func start(_ options: CoralogixExporterOptions = ReplayMessagesTests.options(),
                       sm: SessionManager = ReplayMessagesTests.sessionManager()) throws -> (CoralogixRum, CapturingSpanUploader) {
        let rum = CoralogixRum(options: options, sessionManager: sm)
        rums.append(rum)
        let uploader = CapturingSpanUploader()
        try XCTUnwrap(rum.coralogixExporter).spanUploader = uploader
        return (rum, uploader)
    }

    /// Exports one event stamped with `sessionId` through RUM's own exporter and returns its hasRecording.
    private func exportedHasRecording(_ sessionId: String, _ rum: CoralogixRum, _ uploader: CapturingSpanUploader,
                                      file: StaticString = #filePath, line: UInt = #line) throws -> Bool? {
        let before = uploader.cxRumPayloads().count
        let span = makeSamplingSpan(eventType: .log, extraAttributes: [Keys.sessionId.rawValue: AttributeValue(sessionId)])
        _ = try XCTUnwrap(rum.coralogixExporter, file: file, line: line).export(spans: [span], explicitTimeout: nil)
        let payloads = uploader.cxRumPayloads()
        XCTAssertEqual(payloads.count, before + 1, "fixture: the event was exported", file: file, line: line)
        let event = try XCTUnwrap(payloads.last, file: file, line: line)
        XCTAssertEqual(Self.sessionId(of: event), sessionId, "fixture: the event's own session", file: file, line: line)
        return Self.hasRecording(of: event)
    }

    private func awaitEvent(_ rum: CoralogixRum, _ uploader: CapturingSpanUploader, _ description: String,
                            where match: @escaping ([String: Any]) -> Bool) throws -> [String: Any] {
        var hit: [String: Any]?
        let found = expectation(for: NSPredicate { _, _ in
            rum.flush()
            hit = uploader.cxRumPayloads().first(where: match)
            return hit != nil
        }, evaluatedWith: nil)
        wait(for: [found], timeout: 10)
        return try XCTUnwrap(hit, description)
    }

    private func screenshots(_ uploader: CapturingSpanUploader) -> [[String: Any]] {
        uploader.cxRumPayloads().filter { Self.type(of: $0) == CoralogixEventType.screenshot.rawValue }
    }

    private static func resolvesByName(_ view: UIView, _ tag: String,
                                       file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let getter = view.responds(to: NSSelectorFromString(tag))
        let setter = view.responds(to: NSSelectorFromString("set\(tag.prefix(1).uppercased())\(tag.dropFirst()):"))
        XCTAssertTrue(getter, "'\(tag)' does not resolve by name", file: file, line: line)
        XCTAssertTrue(setter, "'\(tag)' has no setter by name", file: file, line: line)
        return getter && setter
    }

    private static func type(of event: [String: Any]) -> String? {
        (event[Keys.eventContext.rawValue] as? [String: Any])?[Keys.type.rawValue] as? String
    }

    private static func screenshotId(of event: [String: Any]) -> String? {
        (event[Keys.screenshotContext.rawValue] as? [String: Any])?[Keys.screenshotId.rawValue] as? String
    }

    private static func sessionId(of event: [String: Any]) -> String? {
        (event[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.sessionId.rawValue] as? String
    }

    private static func hasRecording(of event: [String: Any]) -> Bool? {
        (event[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.hasRecording.rawValue] as? Bool
    }

    private static func logMessage(of event: [String: Any]) -> String? {
        (event[Keys.logContext.rawValue] as? [String: Any])?[Keys.message.rawValue] as? String
    }

    private static func internalEventName(of event: [String: Any]) -> String? {
        (event[Keys.internalContext.rawValue] as? [String: Any])?[Keys.event.rawValue] as? String
    }

    static func options() -> CoralogixExporterOptions {
        makeSamplingOptions(sampleRate: 100, exclude: [])
    }

    static func sessionManager() -> SessionManager {
        SessionManager(snapshotStore: SessionSnapshotStore())
    }

    private static func backdate(_ sm: SessionManager, seconds: TimeInterval) {
        guard var metadata = sm.sessionMetadata else { return XCTFail("no session") }
        metadata.sessionCreationDate = Date().addingTimeInterval(-seconds).timeIntervalSince1970
        sm.sessionMetadata = metadata
    }

    private static func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
}

// MARK: - Internal header

final class ReplayInternalHeaderTests: XCTestCase {

    private var rum: CoralogixRum?
    private let captured = SpanBox()

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
        URLProtocol.registerClass(InternalHeaderStubProtocol.self)
        let box = captured
        CoralogixExporter.testExportCallback = { box.add($0) }
        rum = CoralogixRum(options: CoralogixExporterOptions(coralogixDomain: .EU2, environment: "test",
                                                             application: "HeaderTest", version: "1.0",
                                                             publicKey: "test-key", instrumentations: [.network: true]))
    }

    override func tearDown() {
        rum?.shutdown()
        rum = nil
        CoralogixRum.isInitialized = false
        CoralogixExporter.testExportCallback = nil
        URLProtocol.unregisterClass(InternalHeaderStubProtocol.self)
        super.tearDown()
    }

    /// RED-now. A URLSession request carrying the internal header (any name case) produces no network span; one
    /// without it still does.
    func testURLSession_internalHeader_isNotInstrumented() throws {
        let base = "\(InternalHeaderStubProtocol.scheme)://replay.test"
        perform("\(base)/internal-canonical", headers: ["X-Coralogix-Internal": "1"])
        perform("\(base)/internal-lower", headers: ["x-coralogix-internal": "1"])
        perform("\(base)/internal-upper", headers: ["X-CORALOGIX-INTERNAL": "1"])
        perform("\(base)/plain")

        awaitNetworkSpan(urlContains: "/plain")
        XCTAssertEqual(networkUrls().filter { $0.contains("/internal-") }, [], "an internal request was instrumented")
    }

    /// RED-now. A hybrid-reported request whose headers carry the internal header (any name case) produces no
    /// network span; one without it still does.
    func testHybridRequest_internalHeader_isNotInstrumented() throws {
        let rum = try XCTUnwrap(rum)
        let base = "https://hybrid.replay.test"
        for (path, name) in [("internal-canonical", "X-Coralogix-Internal"), ("internal-lower", "x-coralogix-internal"),
                             ("internal-upper", "X-CORALOGIX-INTERNAL")] {
            rum.setNetworkRequestContext(dictionary: Self.hybrid(url: "\(base)/\(path)", headers: [name: "1"]))
        }
        rum.setNetworkRequestContext(dictionary: Self.hybrid(url: "\(base)/plain", headers: ["Accept": "*/*"]))

        awaitNetworkSpan(urlContains: "hybrid.replay.test/plain")
        XCTAssertEqual(networkUrls().filter { $0.contains("/internal-") }, [], "an internal request was instrumented")
    }

    private func perform(_ url: String, headers: [String: String] = [:]) {
        var request = URLRequest(url: URL(string: url)!)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let done = expectation(description: url)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 5)
    }

    private func networkUrls() -> [String] {
        captured.all.compactMap { span in
            guard span.attributes[Keys.eventType.rawValue]?.description == CoralogixEventType.networkRequest.rawValue else {
                return nil
            }
            return span.attributes[SemanticAttributes.httpUrl.rawValue]?.description
        }
    }

    private func awaitNetworkSpan(urlContains: String) {
        let rum = rum
        let found = expectation(for: NSPredicate { [weak self] _, _ in
            rum?.flush()
            return self?.networkUrls().contains { $0.contains(urlContains) } ?? false
        }, evaluatedWith: nil)
        wait(for: [found], timeout: 10)
    }

    private static func hybrid(url: String, headers: [String: String]) -> [String: Any] {
        [Keys.url.rawValue: url, Keys.host.rawValue: "hybrid.replay.test", Keys.method.rawValue: "POST",
         Keys.statusCode.rawValue: 200, Keys.schema.rawValue: "https", Keys.requestHeaders.rawValue: headers]
    }
}

private final class InternalHeaderStubProtocol: URLProtocol {
    static let scheme = "replayheadertest"
    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == scheme }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class SpanBox: @unchecked Sendable {
    private let lock = NSLock()
    private var spans: [SpanData] = []
    func add(_ more: [SpanData]) { lock.lock(); spans.append(contentsOf: more); lock.unlock() }
    var all: [SpanData] { lock.lock(); defer { lock.unlock() }; return spans }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [[String: Any]] = []
    func add(_ event: [String: Any]) { lock.lock(); events.append(event); lock.unlock() }
    var all: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return events }
}

private final class Recorded: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RumToReplay] = []
    func add(_ message: RumToReplay) { lock.lock(); recorded.append(message); lock.unlock() }
    var messages: [RumToReplay] { lock.lock(); defer { lock.unlock() }; return recorded }
}
