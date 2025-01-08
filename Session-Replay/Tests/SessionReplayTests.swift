//
//  SessionReplayTests.swift
//  session_replayTests
//
//  Created by Tomer Har Yoffi on 25/12/2024.
//

import XCTest
@testable import Session_Replay

class SessionReplayTests: XCTestCase {

    func testStartSessionRecording_startsRecordingWhenNotAlreadyRecording() {
        let mockOptions = SessionReplayOptions(imageRecordingType: true)
        SessionReplay.initializeWithOptions(sessionReplayOptions: mockOptions)
        SessionReplay.shared.startSessionRecording()

        if let isRecording = SessionReplay.shared.sessionReplayModel?.isRecording {
            XCTAssertTrue(isRecording, "Session recording should start when not already recording.")
        }
        if let captureTimer = SessionReplay.shared.sessionReplayModel?.captureTimer {
            XCTAssertNotNil(captureTimer, "Capture timer should be initialized.")
        }
    }

    func testStartSessionRecording_doesNotStartWhenAlreadyRecording() {
        let mockOptions = SessionReplayOptions(imageRecordingType: true)
        SessionReplay.initializeWithOptions(sessionReplayOptions: mockOptions)
        SessionReplay.shared.startSessionRecording()
        if let isRecording = SessionReplay.shared.sessionReplayModel?.isRecording {
            XCTAssertTrue(isRecording, "Session recording should remain true when already recording.")
        }
        let beforeCaptureTimer = SessionReplay.shared.sessionReplayModel?.captureTimer
        SessionReplay.shared.startSessionRecording()
        let afterCaptureTimer = SessionReplay.shared.sessionReplayModel?.captureTimer
        XCTAssertEqual(beforeCaptureTimer, afterCaptureTimer, "Capture timer should not be re-initialized when already recording.")
    }

    func testStopSessionRecording_stopsRecording() {
        SessionReplay.shared.startSessionRecording()
        sleep(1)
        SessionReplay.shared.stopSessionRecording()
        if let isRecording = SessionReplay.shared.sessionReplayModel?.isRecording {
            XCTAssertFalse(isRecording, "Session recording should stop.")
        }
        
        if let captureTimer = SessionReplay.shared.sessionReplayModel?.captureTimer {
           let isValid = captureTimer.isValid
            XCTAssertFalse(isValid, "Capture timer should be invalidated.")
        }
    }

    func testCaptureEvent_capturesImageWhenRecording() {
        let expectation = self.expectation(description: "Timer should trigger captureImage after 3 seconds")
        let options = SessionReplayOptions(imageRecordingType: true)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)

        let mockSessionReplayModel = MockSessionReplayModel(sessionReplayOptions: options)

        SessionReplay.shared.update(sessionReplayModel: mockSessionReplayModel)
        SessionReplay.shared.startSessionRecording()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            SessionReplay.shared.captureEvent()
            XCTAssertEqual(mockSessionReplayModel.captureImageCallCount, 2, "Capture image should be called when recording.")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 4.0, handler: nil)
    }

    func testCaptureEvent_doesNotCaptureImageWhenNotRecording() {
        SessionReplay.shared.captureEvent()
        if let sessionReplayModel = SessionReplay.shared.sessionReplayModel {
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
