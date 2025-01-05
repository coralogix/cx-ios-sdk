//
//  SessionReplayTests.swift
//  session_replayTests
//
//  Created by Tomer Har Yoffi on 25/12/2024.
//

import XCTest
@testable import session_replay

class SessionReplayTests: XCTestCase {
    var sessionReplay: SessionReplay!

    override func setUp() {
        super.setUp()
        let mockOptions = SessionReplayOptions(recordingType: .image)
        sessionReplay = SessionReplay(sessionId: "B7761BF4-F256-4BA4-969F-DC4533483CC9", sessionReplayOptions: mockOptions)
    }

    override func tearDown() {
        sessionReplay = nil
        super.tearDown()
    }

    func testStartSessionRecording_startsRecordingWhenNotAlreadyRecording() {
        sessionReplay.startSessionRecording()

        if let isRecording = sessionReplay.sessionReplayModel?.isRecording {
            XCTAssertTrue(isRecording, "Session recording should start when not already recording.")
        }
        if let captureTimer = sessionReplay.sessionReplayModel?.captureTimer {
            XCTAssertNotNil(captureTimer, "Capture timer should be initialized.")
        }
    }

    func testStartSessionRecording_doesNotStartWhenAlreadyRecording() {
        sessionReplay.startSessionRecording()
        if let isRecording = sessionReplay.sessionReplayModel?.isRecording {
            XCTAssertTrue(isRecording, "Session recording should remain true when already recording.")
        }
        let beforeCaptureTimer = sessionReplay.sessionReplayModel?.captureTimer
        sessionReplay.startSessionRecording()
        let afterCaptureTimer = sessionReplay.sessionReplayModel?.captureTimer
        XCTAssertEqual(beforeCaptureTimer, afterCaptureTimer, "Capture timer should not be re-initialized when already recording.")
    }

    func testStopSessionRecording_stopsRecording() {
        sessionReplay.startSessionRecording()
        sleep(1)
        sessionReplay.stopSessionRecording()
        if let isRecording = sessionReplay.sessionReplayModel?.isRecording {
            XCTAssertFalse(isRecording, "Session recording should stop.")
        }
        
        if let captureTimer = sessionReplay.sessionReplayModel?.captureTimer {
           let isValid = captureTimer.isValid
            XCTAssertFalse(isValid, "Capture timer should be invalidated.")
        }
    }

    func testCaptureEvent_capturesImageWhenRecording() {
        let expectation = self.expectation(description: "Timer should trigger captureImage after 3 seconds")
        let mockOptions = SessionReplayOptions(recordingType: .image)
        let mockSessionReplayModel = MockSessionReplayModel(sessionId: "testSession", sessionReplayOptions: mockOptions)

        sessionReplay.sessionReplayModel = mockSessionReplayModel
        sessionReplay.startSessionRecording()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.sessionReplay.captureEvent()
            XCTAssertEqual(mockSessionReplayModel.captureImageCallCount, 2, "Capture image should be called when recording.")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 4.0, handler: nil)
    }

    func testCaptureEvent_doesNotCaptureImageWhenNotRecording() {
        sessionReplay.captureEvent()
        if let sessionReplayModel = sessionReplay.sessionReplayModel {
            XCTAssertEqual(sessionReplayModel.trackNumber, 0, "Capture image should not be called when not recording.")
        }
    }
}

// Mock SessionReplayModel
class MockSessionReplayModel: SessionReplayModel {
    var captureImageCallCount = 0

    override func captureImage() {
        captureImageCallCount += 1
    }
}
