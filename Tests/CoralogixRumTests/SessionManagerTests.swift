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
        XCTAssertFalse(sessionManager.doesSessionhasRecording())

        // After setting, should be true
        sessionManager.hasRecording = true
        XCTAssertTrue(sessionManager.doesSessionhasRecording())
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
}
