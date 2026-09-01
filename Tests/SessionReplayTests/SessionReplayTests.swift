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

extension SessionReplayTests {

    /// A host calling `captureEvent` asked for this frame. Deduplication answering that with
    /// silence leaves a void-returning public API with nothing to report, so the capture is
    /// marked manual and exempted — the same exemption a tap frame gets.
    func testCaptureEventFromTheHostIsMarkedManualSoItIsNotDeduplicated() throws {
        SdkManager.shared.register(coralogixInterface: MockCoralogix())
        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        let model = MockSessionReplayModel(sessionReplayOptions: options)
        model.isRecording = true
        SessionReplay.shared.update(sessionReplayModel: model)

        _ = SessionReplay.shared.captureEvent(properties: [Keys.event.rawValue: "screenshot"])

        let properties = try XCTUnwrap(model.captureImageProperties)
        XCTAssertEqual(properties[Keys.isManual.rawValue] as? Bool, true,
                       "a capture the host requested directly must be exempt from deduplication")
    }

    /// The SDK's own instrumentation reserves a slot first, so it must not pick up the exemption —
    /// otherwise every periodic tick bypasses deduplication and the replay ships identical frames.
    func testInstrumentationCaptureIsNotMarkedManual() throws {
        SdkManager.shared.register(coralogixInterface: MockCoralogix())
        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)
        let model = MockSessionReplayModel(sessionReplayOptions: options)
        model.isRecording = true
        SessionReplay.shared.update(sessionReplayModel: model)

        // What recordScreenshotForSpan passes: a reserved page and segment index.
        _ = SessionReplay.shared.captureEvent(properties: [
            Keys.page.rawValue: 0,
            Keys.segmentIndex.rawValue: 4,
            Keys.screenshotId.rawValue: "sid"
        ])

        let properties = try XCTUnwrap(model.captureImageProperties)
        XCTAssertNil(properties[Keys.isManual.rawValue],
                     "a capture the SDK originated must stay subject to deduplication")
    }
}

/// Stands in the UIKit walk so the capture can run without a foreground scene, but leaves the
/// real deduplication, encoding and completion path intact.
final class StubbedWalkModel: SessionReplayModel {
    let frameImage: UIImage
    private let lock = NSLock()
    private var _savedCount = 0

    var savedCount: Int { lock.lock(); defer { lock.unlock() }; return _savedCount }

    init(options: SessionReplayOptions, image: UIImage) {
        self.frameImage = image
        super.init(sessionReplayOptions: options)
    }

    override func prepareCapturedFrameOnMain(properties: [String: Any]?) -> CapturedFrame? {
        CapturedFrame(image: frameImage, maskRects: [])
    }

    override func saveScreenshotToFileSystem(screenshotData: Data, properties: [String: Any]?) {
        lock.lock(); defer { lock.unlock() }; _savedCount += 1
    }
}

extension SessionReplayTests {

    /// End to end through the public completion overload, with the real deduplication path: two
    /// identical captures a host asked for must both ship. `captureEvent` returns void to the
    /// host, so answering the second with silence leaves it no way to know the frame was dropped.
    func testPublicCaptureEventTwiceOnAnUnchangedScreen_shipsBothFrames() {
        SdkManager.shared.register(coralogixInterface: MockCoralogix())
        let options = SessionReplayOptions(recordingType: .image)
        SessionReplay.initializeWithOptions(sessionReplayOptions: options)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { ctx in
            UIColor.magenta.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let model = StubbedWalkModel(options: options, image: image)
        model.isRecording = true
        model.updateSessionId(with: "session-\(UUID().uuidString)")
        SessionReplay.shared.update(sessionReplayModel: model)

        func capture() -> Result<Void, CaptureEventError> {
            let answered = expectation(description: "capture answered")
            var outcome: Result<Void, CaptureEventError>?
            let lock = NSLock()
            SessionReplay.shared.captureEvent(properties: nil) { result in
                lock.lock(); outcome = result; lock.unlock()
                answered.fulfill()
            }
            wait(for: [answered], timeout: 5)
            lock.lock(); defer { lock.unlock() }
            return outcome ?? .failure(.captureFailed)
        }

        guard case .success = capture() else {
            XCTFail("The first host capture must ship")
            return
        }
        guard case .success = capture() else {
            XCTFail("The second host capture must ship too — identical pixels, but explicitly requested")
            return
        }
        XCTAssertEqual(model.savedCount, 2, "Both requested frames must reach the save path")
    }
}

class MockSessionReplayModel3: SessionReplayModel {
    var updatedSessionId: String?

    override func updateSessionId(with sessionId: String) {
        updatedSessionId = sessionId
    }
}

