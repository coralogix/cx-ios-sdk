//
//  SessionReplayTests.swift
//  session_replayTests
//
//  Created by Coralogix DEV TEAM on 25/12/2024.
//

import XCTest
@testable import CoralogixInternal
@testable import SessionReplay

class SessionReplayTests: XCTestCase {

    func testStartSessionRecording_startsRecordingWhenNotAlreadyRecording() {
        let mockOptions = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: mockOptions)
        SessionReplay.shared.startRecording()

        if let isRecording = SessionReplay.shared.sessionReplayModel?.isRecording {
            XCTAssertTrue(isRecording, "Session recording should start when not already recording.")
        }
        if let captureTimer = SessionReplay.shared.sessionReplayModel?.captureTimer {
            XCTAssertNotNil(captureTimer, "Capture timer should be initialized.")
        }
    }

    func testStartSessionRecording_doesNotStartWhenAlreadyRecording() {
        let mockOptions = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: mockOptions)
        SessionReplay.shared.startRecording()
        if let isRecording = SessionReplay.shared.sessionReplayModel?.isRecording {
            XCTAssertTrue(isRecording, "Session recording should remain true when already recording.")
        }
        let beforeCaptureTimer = SessionReplay.shared.sessionReplayModel?.captureTimer
        SessionReplay.shared.startRecording()
        let afterCaptureTimer = SessionReplay.shared.sessionReplayModel?.captureTimer
        XCTAssertEqual(beforeCaptureTimer, afterCaptureTimer, "Capture timer should not be re-initialized when already recording.")
    }

    func testStopSessionRecording_stopsRecording() {
        let expectation = self.expectation(description: "Delay between start and stop")
        SessionReplay.shared.startRecording()
        
        // Give some time between start and stop, but with expectation instead of sleep
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.5, handler: nil)
        
        SessionReplay.shared.stopRecording()
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
        // Initialize the SRNetworkManager
        SdkManager.shared.register(coralogixInterface: MockCoralogix())
        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)

        let mockSessionReplayModel = MockSessionReplayModel(sessionReplayOptions: options)

        SessionReplay.shared.update(sessionReplayModel: mockSessionReplayModel)
        SessionReplay.shared.startRecording()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let timestemp: TimeInterval = Date().timeIntervalSince1970
            _ = SessionReplay.shared.captureEvent(properties: [Keys.timestamp.rawValue: timestemp])
            XCTAssertEqual(mockSessionReplayModel.captureImageCallCount, 1, "Capture image should be called when recording.")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 4.0, handler: nil)
    }
    
    func testUpdate_whenDummyInstance_logsAndReturns() {
        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)

        SessionReplay.shared.isDummyInstance = true
        SessionReplay.shared.sessionReplayModel = nil
        SessionReplay.shared.update(sessionId: "new-session")

        // Nothing to assert directly without log capture
        // You can assert that updateSessionId is *not* called
        XCTAssertNil((SessionReplay.shared.sessionReplayModel as? MockSessionReplayModel3)?.updatedSessionId)
    }
    
    func testUpdate_whenNoSessionReplayModel_logsErrorAndReturns() {
        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        SessionReplay.shared.isDummyInstance = false
        SessionReplay.shared.sessionReplayModel = nil
        
        SessionReplay.shared.update(sessionId: "new-session")
        
        XCTAssertNil((SessionReplay.shared.sessionReplayModel as? MockSessionReplayModel3)?.updatedSessionId)
    }
    
    func testUpdate_callsUpdateSessionIdOnModel() {
        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        SessionReplay.shared.isDummyInstance = false
        let mockSessionReplayModel = MockSessionReplayModel3(sessionReplayOptions: options)
        SessionReplay.shared.sessionReplayModel = mockSessionReplayModel
        SessionReplay.shared.update(sessionId: "12345-session")
        
        XCTAssertEqual((SessionReplay.shared.sessionReplayModel as? MockSessionReplayModel3)?.updatedSessionId, "12345-session")
    }
    
    func testCreateDummyInstanceSetsCorrectFlags() {
        let options = SessionReplayOptions(sessionRecordingSampleRate: 50)
        let dummy = SessionReplay.createDummyInstance(options)
        
        XCTAssertTrue(dummy.isDummyInstance, "Expected isDummyInstance to be true")
        XCTAssertEqual(dummy.sessionReplayOptions?.sessionRecordingSampleRate, 50)
    }
    
    func testCreateDummyInstanceWithNilOptions() {
        let dummy = SessionReplay.createDummyInstance()
        
        XCTAssertTrue(dummy.isDummyInstance, "Expected isDummyInstance to be true")
        XCTAssertNil(dummy.sessionReplayOptions, "Expected options to be nil")
    }
    
    func testCaptureEventSkippedWhenSdkIsIdle() {
        let mockCoralogix = MockCoralogix()
        mockCoralogix.idle = true
        SdkManager.shared.register(coralogixInterface: mockCoralogix)

        let options = SessionReplayOptions(recordingType: .image)
        let mockSessionReplayModel = MockSessionReplayModel(sessionReplayOptions: options)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        SessionReplay.shared.sessionReplayModel = mockSessionReplayModel
        SessionReplay.shared.isDummyInstance = false
        
        let result = SessionReplay.shared.captureEvent(properties: ["key": "value"])

        switch result {
        case .success: 
            XCTFail("Expected .failure(.sdkIdle) but got success")
        case .failure(let error):
            XCTAssertEqual(error, .sdkIdle)
        }
    }
    
    func testCaptureEventSkippedWhenIsDummyInstance() {
        let options = SessionReplayOptions(recordingType: .image)
        let mockSessionReplayModel = MockSessionReplayModel(sessionReplayOptions: options)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        SessionReplay.shared.sessionReplayModel = mockSessionReplayModel
        SessionReplay.shared.isDummyInstance = true
        let result = SessionReplay.shared.captureEvent(properties: ["key": "value"])

        switch result {
        case .success:
            XCTFail("Expected .failure(.dummyInstance) but got success")
        case .failure(let error):
            XCTAssertEqual(error, .dummyInstance)
        }
    }
    
    func testCaptureEventSkippedWhenMissingSessionReplyOptions() {
        let mockCoralogix = MockCoralogix()
        mockCoralogix.idle = false
        SdkManager.shared.register(coralogixInterface: mockCoralogix)
        
        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        SessionReplay.shared.sessionReplayModel = nil
        SessionReplay.shared.isDummyInstance = false

        let result = SessionReplay.shared.captureEvent(properties: ["key": "value"])

        switch result {
        case .success:
            XCTFail("Expected .failure(.missingSessionReplayOptions) but got success")
        case .failure(let error):
            XCTAssertEqual(error, .missingSessionReplayOptions)
        }
    }
    
    func testCaptureEventSkippedWhenNotRecording() {
        let mockCoralogix = MockCoralogix()
        mockCoralogix.idle = false
        SdkManager.shared.register(coralogixInterface: mockCoralogix)
        
        let options = SessionReplayOptions(recordingType: .image)
        let mockSessionReplayModel = MockSessionReplayModel(sessionReplayOptions: options)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        SessionReplay.shared.sessionReplayModel = mockSessionReplayModel
        let result = SessionReplay.shared.captureEvent(properties: ["key": "value"])

        switch result {
        case .success:
            XCTFail("Expected .failure(.notRecording) but got success")
        case .failure(let error):
            XCTAssertEqual(error, .notRecording)
        }
    }

    /// A rejection that returns before the model runs still has to hand the caller's screenshot
    /// index back. Left burned, the replay stream starts at a page and segment the player has no
    /// frames for — every upload succeeds and the recording is still unplayable.
    func testCaptureEventRejectedBeforeTheModelReturnsTheCallerScreenshotIndex() {
        let mockCoralogix = MockCoralogix()
        mockCoralogix.idle = false
        SdkManager.shared.register(coralogixInterface: mockCoralogix)

        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        SessionReplay.shared.sessionReplayModel = MockSessionReplayModel(sessionReplayOptions: options)

        let result = SessionReplay.shared.captureEvent(
            properties: [Keys.segmentIndex.rawValue: 7, Keys.page.rawValue: 0]
        )

        if case .failure(let error) = result {
            XCTAssertEqual(error, .notRecording)
        } else {
            XCTFail("Expected .failure(.notRecording) but got success")
        }
        XCTAssertEqual(mockCoralogix.revertScreenshotCounterCallCount, 1,
                       "a caller-allocated index must be returned when the capture is rejected")
    }

    /// Only an index the caller actually took is ours to give back; it signals that by putting
    /// `segmentIndex` in the properties. Reverting without one would corrupt the counter downwards.
    func testCaptureEventRejectionWithoutACallerIndexDoesNotRevert() {
        let mockCoralogix = MockCoralogix()
        mockCoralogix.idle = false
        SdkManager.shared.register(coralogixInterface: mockCoralogix)

        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        SessionReplay.shared.sessionReplayModel = MockSessionReplayModel(sessionReplayOptions: options)

        let result = SessionReplay.shared.captureEvent(properties: ["key": "value"])

        // Assert the rejection was actually reached: without this the revert count alone would
        // read as 0 for a capture that was never rejected in the first place.
        if case .failure(let error) = result {
            XCTAssertEqual(error, .notRecording)
        } else {
            XCTFail("Expected .failure(.notRecording) but got success")
        }
        XCTAssertEqual(mockCoralogix.revertScreenshotCounterCallCount, 0,
                       "an index the caller never took is not ours to give back")
    }
}

class MockSessionReplayModel3: SessionReplayModel {
    var updatedSessionId: String?

    override func updateSessionId(with sessionId: String) {
        updatedSessionId = sessionId
    }
}

