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

    // MARK: - Session rotation contract (24h-session bug)
    //
    // These four tests characterise the rotation gap that produces 20–24h
    // sessions in production:
    //  - Bug #1: `getSessionMetadata` skips the 1h rotation while idle
    //  - Bug #2: span-emission paths read `.sessionMetadata` directly,
    //            never invoking rotation
    //  - Bug #3: `lastSnapshotEventTime` carries over across rotations,
    //            suppressing the first snapshot of a fresh session for ≤60s
    //
    // Each test is designed to FAIL on current code and PASS after the fix.

    /// Bug #1: an idle session that has lived longer than an hour must still rotate
    /// when `getSessionMetadata()` is queried. Today the rotation branch is gated by
    /// `isIdle == false`, so a stale idle session is returned unchanged.
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

    /// Bug #1 (callback wiring): the rotation that recovers a stale idle session
    /// must also notify listeners (SessionReplay, sampling re-roll) via the two
    /// callbacks. Today the rotation never fires, so neither callback runs.
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

    /// Bug #3: `lastSnapshotEventTime` must reset on rotation so a fresh session
    /// can emit its first snapshot immediately. Today the value carries over,
    /// suppressing the first non-error/non-navigation snapshot of the new session
    /// for up to 60s after rotation.
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
}
