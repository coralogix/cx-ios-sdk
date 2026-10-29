//
//  SessionManagerTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 09/07/2025.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

class SessionManagerTests: XCTestCase {
    var sessionManager: SessionManager!

    override func setUp() {
        super.setUp()
        sessionManager = SessionManager()
    }

    override func tearDown() {
        sessionManager = nil
        super.tearDown()
    }

    func testInitCreatesSessionMetadata() {
        let metadata = sessionManager.getSessionMetadata()
        XCTAssertNotNil(metadata)
        XCTAssertFalse(metadata!.sessionId.isEmpty)
    }

    func testSetupSessionMetadataChangesSession() {
        let oldSessionId = sessionManager.getSessionMetadata()?.sessionId
        sessionManager.setupSessionMetadata()
        let newSessionId = sessionManager.getSessionMetadata()?.sessionId
        XCTAssertNotEqual(oldSessionId, newSessionId)
    }

    func testHasAnHourPassedCreatesNewSession() {
        sessionManager.setupSessionMetadata()

        guard var metadata = sessionManager.getSessionMetadata() else {
            XCTFail("Session metadata should not be nil")
            return
        }

        let oneHourAgo = Date().addingTimeInterval(-3601).timeIntervalSince1970
        metadata.sessionCreationDate = oneHourAgo
        sessionManager.sessionMetadata = metadata
        

        let oldSessionId = metadata.sessionId
        let _ = sessionManager.getSessionMetadata()
        let newSessionId = sessionManager.getSessionMetadata()?.sessionId

        XCTAssertNotEqual(oldSessionId, newSessionId)
    }

    func testIsIdleTriggersSessionReset() {
        sessionManager.setupSessionMetadata()
        sessionManager.lastActivity = Date().addingTimeInterval(-(16 * 60)) // simulate idle

        let expectation = expectation(description: "SessionChangedCallback triggered")
        sessionManager.sessionChangedCallback = { _ in
            expectation.fulfill()
        }

        sessionManager.updateActivityTime()

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testClickAndErrorCounters() {
        sessionManager.incrementClickCounter()
        sessionManager.incrementClickCounter()
        sessionManager.incrementErrorCounter()

        XCTAssertEqual(sessionManager.getClickCount(), 2)
        XCTAssertEqual(sessionManager.getErrorCount(), 1)
    }

    // MARK: - BUGV2-5379: decrementErrorCounter

    func testDecrementErrorCounter_reducesCountByOne() {
        sessionManager.incrementErrorCounter()
        sessionManager.incrementErrorCounter()
        sessionManager.decrementErrorCounter()
        XCTAssertEqual(sessionManager.getErrorCount(), 1)
    }

    func testDecrementErrorCounter_doesNotGoBelowZero() {
        sessionManager.decrementErrorCounter()
        XCTAssertEqual(sessionManager.getErrorCount(), 0, "errorCount must not go negative")
    }

    func testDecrementErrorCounter_incrementThenDecrementEqualsZero() {
        sessionManager.incrementErrorCounter()
        sessionManager.decrementErrorCounter()
        XCTAssertEqual(sessionManager.getErrorCount(), 0)
    }

    func testResetClearsData() {
        sessionManager.incrementClickCounter()
        sessionManager.incrementErrorCounter()
        sessionManager.hasRecording = true

        sessionManager.reset()

        XCTAssertEqual(sessionManager.getClickCount(), 0)
        XCTAssertEqual(sessionManager.getErrorCount(), 0)
        XCTAssertFalse(sessionManager.hasRecording)
    }

    func testShutdownClearsSession() {
        sessionManager.shutdown()

        let metadata = sessionManager.getSessionMetadata()
        XCTAssertEqual(metadata?.sessionId, "")
        XCTAssertEqual(metadata?.sessionCreationDate, 0)
    }

    func testCallbackTriggeredOnSessionChange() {
        var callbackSessionId: String?
        sessionManager.sessionChangedCallback = { sessionId in
            callbackSessionId = sessionId
        }

        sessionManager.setupSessionMetadata()
        XCTAssertNotNil(callbackSessionId)
    }
    
    func testDoesSessionHasRecording() {
        // Initially, should be false
        XCTAssertFalse(sessionManager.doesSessionHasRecording())

        // After setting, should be true
        sessionManager.hasRecording = true
        XCTAssertTrue(sessionManager.doesSessionHasRecording())
    }
    
    func testGetPrevSessionMetadata() {
        // Initially, no previous session
        XCTAssertNil(sessionManager.getPrevSessionMetadata())

        // Simulate a session update
        let oldSessionId = sessionManager.getSessionMetadata()?.sessionId
        sessionManager.setupSessionMetadata()

        // Now the previous session metadata should be the old one
        let prevMetadata = sessionManager.getPrevSessionMetadata()
        XCTAssertNotNil(prevMetadata)
        XCTAssertEqual(prevMetadata?.sessionId, oldSessionId)
    }

    // MARK: - Session rotation contract (regression coverage for the 24h-session bug)
    //
    // Production hit a stale-session bug that produced 20–24h sessions. Three
    // independent gaps contributed; these tests pin each one as a regression:
    //   1. `getSessionMetadata` must rotate stale sessions even when idle
    //      (rotation is purely time-based; idle gates *export*, not rotation).
    //   2. The rotation must fire `sessionEndedCallback` AND `sessionChangedCallback`
    //      so SessionReplay and sampling listeners observe the transition.
    //   3. `lastSnapshotEventTime` must reset on rotation so a fresh session can
    //      emit its first snapshot immediately.
    //   4. A stale rotation must carry the dropped session id forward as
    //      `prevSessionMetadata` (the wire-side `prev_session_id` chain).
    //
    // Scope: these are sequential, single-thread contract tests — they verify
    // state→outcome mappings, not concurrency. Several tests mutate
    // `sessionMetadata`/`lastActivity` directly to set up the "stale + idle"
    // precondition; those writes bypass `sessionLock`, which is safe here only
    // because XCTest runs each test body single-threaded. Real concurrent
    // rotation correctness lives in production paths (see the locking notes in
    // `SessionManager.setupSessionMetadata` / `sessionSpanAttributes`).

    /// Rotation contract: an idle session that has lived longer than an hour must
    /// still rotate when `getSessionMetadata()` is queried. Regression guard for
    /// the previous `isIdle == false` gate that let a stale idle session leak its
    /// ID onto the next emitted span.
    func testHourPassed_whileIdle_rotatesSession() {
        sessionManager.setupSessionMetadata()
        guard var metadata = sessionManager.sessionMetadata else {
            XCTFail("Initial session metadata should not be nil")
            return
        }

        // Force the session into "older than 1h" + "idle (>15 min since activity)" state.
        metadata.sessionCreationDate = Date().addingTimeInterval(-3601).timeIntervalSince1970
        sessionManager.sessionMetadata = metadata
        sessionManager.lastActivity = Date().addingTimeInterval(-(16 * 60))

        let staleSessionId = metadata.sessionId
        let returned = sessionManager.getSessionMetadata()

        XCTAssertNotEqual(returned?.sessionId, staleSessionId,
            "Session must rotate after 1h even when currently idle — otherwise background spans inherit a stale session ID")
    }

    /// Callback wiring contract: the rotation that recovers a stale idle session
    /// must notify listeners (SessionReplay, sampling re-roll) via both
    /// `sessionEndedCallback` and `sessionChangedCallback`. Regression guard for
    /// the case where the rotation branch fired but the listeners were skipped.
    func testHourPassed_whileIdle_firesSessionCallbacks() {
        sessionManager.setupSessionMetadata()
        guard var metadata = sessionManager.sessionMetadata else {
            XCTFail("Initial session metadata should not be nil")
            return
        }
        let staleSessionId = metadata.sessionId
        metadata.sessionCreationDate = Date().addingTimeInterval(-3601).timeIntervalSince1970
        sessionManager.sessionMetadata = metadata
        sessionManager.lastActivity = Date().addingTimeInterval(-(16 * 60))

        let endedExpectation = expectation(description: "sessionEndedCallback fires when stale session rotates")
        let changedExpectation = expectation(description: "sessionChangedCallback fires with a fresh session id")

        sessionManager.sessionEndedCallback = {
            endedExpectation.fulfill()
        }
        sessionManager.sessionChangedCallback = { newId in
            XCTAssertNotEqual(newId, staleSessionId, "Callback must receive the new (rotated) session id")
            changedExpectation.fulfill()
        }

        _ = sessionManager.getSessionMetadata()

        waitForExpectations(timeout: 1.0)
    }

    /// Snapshot-throttle contract: `lastSnapshotEventTime` must reset on rotation
    /// so a fresh session can emit its first snapshot immediately. Regression
    /// guard for the case where the value carried over and suppressed the first
    /// non-error/non-navigation snapshot of the new session for up to 60s.
    func testRotationResetsLastSnapshotEventTime() {
        sessionManager.lastSnapshotEventTime = Date()

        sessionManager.setupSessionMetadata()

        XCTAssertNil(sessionManager.lastSnapshotEventTime,
            "lastSnapshotEventTime must reset on rotation — otherwise a fresh session's first snapshot is suppressed for up to 60s")
    }

    /// When a stale-idle session rotates, the previously-stale ID must be preserved as
    /// `prevSessionMetadata` so the wire-side `prev_session_id` attribute can attribute
    /// the rotation correctly (the dashboard relies on this to chain sessions). Catches
    /// regressions where a rotation drops the previous attribution instead of carrying it.
    func testStaleRotation_preservesStaleIdAsPrevSession() {
        sessionManager.setupSessionMetadata()
        guard var metadata = sessionManager.sessionMetadata else {
            XCTFail("Initial session metadata should not be nil")
            return
        }
        let staleSessionId = metadata.sessionId
        metadata.sessionCreationDate = Date().addingTimeInterval(-3601).timeIntervalSince1970
        sessionManager.sessionMetadata = metadata
        sessionManager.lastActivity = Date().addingTimeInterval(-(16 * 60))

        _ = sessionManager.getSessionMetadata()  // triggers rotation

        let prev = sessionManager.getPrevSessionMetadata()
        XCTAssertEqual(prev?.sessionId, staleSessionId,
            "Rotation must retain the stale session ID as the previous session so spans carry correct prev_session_id attribution")
    }

    // MARK: - Pending snapshot trigger (setUserContext promotion)
    //
    // `setUserContext` arms a one-shot flag so the next exported event is promoted
    // to a snapshot event. These pin the flag's lifecycle: unarmed by default,
    // consumed exactly once, idempotent under repeated arming, and never leaking
    // across a session rotation.

    func testConsumePendingSnapshotTrigger_falseWhenNeverArmed() {
        XCTAssertNil(sessionManager.consumePendingSnapshotTrigger(),
            "An unarmed trigger must not promote any event to a snapshot")
    }

    func testConsumePendingSnapshotTrigger_trueExactlyOnceAfterArming() {
        sessionManager.triggerSnapshotOnNextEvent()

        XCTAssertNotNil(sessionManager.consumePendingSnapshotTrigger(),
            "The first consume after arming must report the pending trigger")
        XCTAssertNil(sessionManager.consumePendingSnapshotTrigger(),
            "Consume is one-shot — a second consume must not promote another event")
    }

    func testConsumePendingSnapshotTrigger_repeatedArmingConsumesOnce() {
        sessionManager.triggerSnapshotOnNextEvent()
        sessionManager.triggerSnapshotOnNextEvent()

        XCTAssertNotNil(sessionManager.consumePendingSnapshotTrigger(),
            "Repeated arming before the next event still promotes exactly one snapshot")
        XCTAssertNil(sessionManager.consumePendingSnapshotTrigger(),
            "Repeated arming must not queue additional promotions")
    }

    func testPendingSnapshotTrigger_clearedBySessionRotation() {
        sessionManager.triggerSnapshotOnNextEvent()

        sessionManager.setupSessionMetadata()

        XCTAssertNil(sessionManager.consumePendingSnapshotTrigger(),
            "A stale trigger must not leak into a fresh session — the rotation's nil throttle already grants the first snapshot")
    }

    func testRestorePendingSnapshotTrigger_reArmsWithinTheSameSession() {
        sessionManager.triggerSnapshotOnNextEvent()
        guard let token = sessionManager.consumePendingSnapshotTrigger() else {
            return XCTFail("Arming must yield a token to consume")
        }

        sessionManager.restorePendingSnapshotTrigger(token)

        XCTAssertNotNil(sessionManager.consumePendingSnapshotTrigger(),
            "A token handed back in the session it was armed in must re-arm the promotion")
    }

    func testRestorePendingSnapshotTrigger_discardedAfterSessionRotation() {
        sessionManager.triggerSnapshotOnNextEvent()
        guard let token = sessionManager.consumePendingSnapshotTrigger() else {
            return XCTFail("Arming must yield a token to consume")
        }

        sessionManager.setupSessionMetadata()
        sessionManager.restorePendingSnapshotTrigger(token)

        XCTAssertNil(sessionManager.consumePendingSnapshotTrigger(),
            "A token from a rotated-out session must be discarded — a delayed beforeSend drop must not promote an event in the fresh session")
    }

    func testRestorePendingSnapshotTrigger_doesNotClobberNewerArm() {
        // Interleaving: token A is consumed, setUserContext(B) arms a fresh token while
        // A's span sits in the customer's beforeSend, then the drop hands A back.
        sessionManager.triggerSnapshotOnNextEvent(
            userContext: UserContext(userId: "user-A", userName: "A", userEmail: "a@example.com", userMetadata: [:]))
        guard let staleToken = sessionManager.consumePendingSnapshotTrigger() else {
            return XCTFail("Arming must yield a token to consume")
        }

        sessionManager.triggerSnapshotOnNextEvent(
            userContext: UserContext(userId: "user-B", userName: "B", userEmail: "b@example.com", userMetadata: [:]))
        sessionManager.restorePendingSnapshotTrigger(staleToken)

        XCTAssertEqual(sessionManager.consumePendingSnapshotTrigger()?.userContext?.userId, "user-B",
            "A handed-back token must not displace a fresher arm — the next promoted snapshot has to report the newest setUserContext identity")
    }

    func testTriggerSnapshotOnNextEvent_expiredSession_armsForTheRotatedSession() {
        // Rotation is lazy — with no span emitted for over an hour, only the arm itself
        // can fire it. A token stamped with the expired session's id could never match
        // any future span, and the rotation would then delete it unconsumed.
        guard var metadata = sessionManager.getSessionMetadata() else {
            return XCTFail("Initial session metadata should not be nil")
        }
        let expiredSessionId = metadata.sessionId
        metadata.sessionCreationDate = Date().addingTimeInterval(-3601).timeIntervalSince1970
        sessionManager.sessionMetadata = metadata

        sessionManager.triggerSnapshotOnNextEvent()

        let token = sessionManager.consumePendingSnapshotTrigger()
        XCTAssertNotNil(token, "Arming on an expired session must still yield a pending token")
        XCTAssertNotEqual(token?.sessionId, expiredSessionId,
            "The token must not be stamped with the expired session no span will ever carry again")
        XCTAssertEqual(token?.sessionId, sessionManager.getSessionMetadata()?.sessionId,
            "The arm must rotate first so the token belongs to the session the next span will actually carry")
    }

    func testShutdown_clearsPendingSnapshotTrigger() {
        sessionManager.triggerSnapshotOnNextEvent(
            userContext: UserContext(userId: "u1", userName: "n", userEmail: "a@b.com", userMetadata: [:]))

        sessionManager.shutdown()

        XCTAssertNil(sessionManager.consumePendingSnapshotTrigger(),
            "shutdown() must release the armed token — with the session id blanked it could never be consumed, only retain the user's identity")
    }

    // MARK: - Crash attribution to the previous-launch session
    //
    // A crash is captured on the *next* launch, after a fresh session has already
    // been created. `lastLaunchSessionSpanAttributes` surfaces the session that was
    // live when the previous launch ended (captured once at init into
    // `lastLaunchSession`) so crash instrumentation can burn the crash under the
    // session that actually crashed.

    func testLastLaunchSessionSpanAttributes_returnsPreviousLaunchSession() {
        sessionManager.lastLaunchSession = LastLaunchSession(sessionId: "crashed-session-abc",
                                                             creationDate: 1_600_000_000,
                                                             sampledIn: true)

        let attrs = Dictionary(uniqueKeysWithValues: sessionManager.lastLaunchSessionSpanAttributes())
        XCTAssertEqual(attrs[Keys.sessionId.rawValue], "crashed-session-abc",
            "Crash span must carry the crashed session id, not the session created on relaunch")
        XCTAssertEqual(attrs[Keys.sessionCreationDate.rawValue], "1600000000",
            "Crash span must carry the crashed session's creation date")
    }

    /// A crash with no previous-launch record (a locked-keychain read, or a crash before the SDK
    /// ever initialized) must not inherit a sampled-out relaunch's stamp, or it is dropped and
    /// purged as resolved.
    func testLastLaunchSessionSpanAttributes_noPreviousLaunch_stampsSampledInOnly() {
        sessionManager.lastLaunchSession = nil

        let attrs = Dictionary(uniqueKeysWithValues: sessionManager.lastLaunchSessionSpanAttributes())
        XCTAssertEqual(attrs, [Keys.spanSessionSampledIn.rawValue: "true"],
            "With no record, only the sampling stamp is overridden; the session identity stays the relaunch's")
    }

    /// Every rotation rebuilds `SessionMetadata`, which re-reads `old*` from a keychain that by then
    /// holds this launch's sessions. A crash recovered after a rotation must still carry the crashed
    /// launch's identity and decision.
    func testLastLaunchSessionSpanAttributes_unchangedByRotation() {
        sessionManager.lastLaunchSession = LastLaunchSession(sessionId: "crashed-session-abc",
                                                             creationDate: 1_600_000_000,
                                                             sampledIn: true)
        sessionManager.samplingRoller = { false }

        sessionManager.setupSessionMetadata()
        sessionManager.setupSessionMetadata()

        let after = Dictionary(uniqueKeysWithValues: sessionManager.lastLaunchSessionSpanAttributes())
        XCTAssertEqual(after[Keys.sessionId.rawValue], "crashed-session-abc")
        XCTAssertEqual(after[Keys.sessionCreationDate.rawValue], "1600000000")
        XCTAssertEqual(after[Keys.spanSessionSampledIn.rawValue], "true",
            "A rotation that rolled sampled-out must not relabel the crashed session as sampled out")
    }

    func testLastLaunchSession_readsPreviousLaunchFieldsOfFirstMetadata() {
        let keychain = MockKeyschainManager()
        _ = SessionMetadata(sessionId: "crashed-session", sessionCreationDate: 1_600_000_000, using: keychain)
        keychain.writeStringToKeychain(service: Keys.service.rawValue,
                                       key: Keys.keySessionSampledIn.rawValue,
                                       value: "true")
        let relaunch = SessionMetadata(sessionId: "fresh-session", sessionCreationDate: 1_700_000_000, using: keychain)

        XCTAssertEqual(LastLaunchSession(previousOf: relaunch),
                       LastLaunchSession(sessionId: "crashed-session", creationDate: 1_600_000_000, sampledIn: true))
    }

    // MARK: - startSessionSpanAttributes: a hybrid request's start session, as its spans recorded it

    private func values(_ attributes: [(key: String, value: AttributeValue?)]) -> [String: AttributeValue] {
        Dictionary(uniqueKeysWithValues: attributes.compactMap { attribute in attribute.value.map { (attribute.key, $0) } })
    }

    /// A request reported after its session ended carries the `prev_*` breadcrumbs a span made in that
    /// session recorded, not the ones of the session live when it completes.
    func testStartSessionSpanAttributes_endedSession_carriesItsOwnPrevSessionBreadcrumbs() throws {
        // The test host's keychain keeps nothing, so the breadcrumbs are seeded through a mock one.
        let keychain = MockKeyschainManager()
        _ = SessionMetadata(sessionId: "before-start", sessionCreationDate: 1_600_000_000, using: keychain)
        sessionManager.sessionMetadata = SessionMetadata(sessionId: "seeded",
                                                         sessionCreationDate: Date().timeIntervalSince1970,
                                                         using: keychain)
        sessionManager.setupSessionMetadata()
        let startSessionId = try XCTUnwrap(sessionManager.getSessionMetadata()?.sessionId)
        let madeInIt = Dictionary(uniqueKeysWithValues: sessionManager.sessionSpanAttributes())
        XCTAssertEqual(madeInIt[Keys.prevSessionId.rawValue], "before-start", "Precondition: the start session has breadcrumbs")

        sessionManager.setupSessionMetadata()
        let live = Dictionary(uniqueKeysWithValues: sessionManager.sessionSpanAttributes())
        XCTAssertNotEqual(live[Keys.prevSessionId.rawValue], "before-start", "Precondition: the live session's breadcrumbs differ")

        let stamped = values(try XCTUnwrap(sessionManager.startSessionSpanAttributes(startSessionId)))
        XCTAssertEqual(stamped[Keys.sessionId.rawValue], .string(startSessionId))
        for key in [Keys.prevPid.rawValue, Keys.prevSessionId.rawValue, Keys.prevSessionCreationDate.rawValue] {
            XCTAssertNotNil(madeInIt[key], key)
            XCTAssertEqual(stamped[key], madeInIt[key].map(AttributeValue.string), key)
        }
    }

    /// The live session's stamp brings the view read with it, so a rotation between resolving the session
    /// and making the span cannot pair this session's id with the next session's view.
    func testStartSessionSpanAttributes_liveSession_carriesTheViewReadWithIt() throws {
        sessionManager.viewProvider = { (name: "checkout", number: 3) }
        let sessionId = try XCTUnwrap(sessionManager.getSessionMetadata()?.sessionId)

        let stamped = values(try XCTUnwrap(sessionManager.startSessionSpanAttributes(sessionId)))
        XCTAssertEqual(stamped[Keys.spanViewName.rawValue], .string("checkout"))
        XCTAssertEqual(stamped[Keys.spanViewNumber.rawValue], .int(3))
    }
}
