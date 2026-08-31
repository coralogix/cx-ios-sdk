//
//  CaptureCompletionOutcomeTests.swift
//  Session-Replay-Tests
//
//  The completion has to agree with what actually happened to the frame, because that is what
//  decides whether a span advertises a screenshot. Each test asserts the reported outcome and
//  whether the frame reached the save path, so the two cannot drift apart.
//

import XCTest
import UIKit
import CoralogixInternal
@testable import SessionReplay

final class CaptureCompletionOutcomeTests: XCTestCase {

    /// Stubs the save so nothing touches disk or the network; counts what would have shipped.
    private final class SaveCountingModel: SessionReplayModel {
        private let lock = NSLock()
        private var _savedCount = 0

        var savedCount: Int {
            lock.lock(); defer { lock.unlock() }; return _savedCount
        }

        override func saveScreenshotToFileSystem(screenshotData: Data, properties: [String: Any]?) {
            lock.lock(); defer { lock.unlock() }; _savedCount += 1
        }
    }

    private var model: SaveCountingModel!

    override func setUp() {
        super.setUp()
        model = SaveCountingModel()
    }

    override func tearDown() {
        model = nil
        super.tearDown()
    }

    // Solid-colour image, so two calls with the same colour are byte-identical after encoding.
    private func solidImage(red: CGFloat, size: CGFloat = 8) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor(red: red, green: 0, blue: 0, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    /// Carries a completion's result across the queue boundary. The completion runs on
    /// `encodingQueue` (or the main queue, for the hop test) while the assertions run on the test
    /// thread, so the handoff is guarded rather than relying on the expectation for ordering.
    private final class Answer {
        private let lock = NSLock()
        private var _outcome: Result<Void, CaptureEventError>?
        private var _savedCount = 0

        func record(_ outcome: Result<Void, CaptureEventError>, savedCount: Int) {
            lock.lock(); defer { lock.unlock() }
            _outcome = outcome
            _savedCount = savedCount
        }

        var value: (outcome: Result<Void, CaptureEventError>?, savedCount: Int) {
            lock.lock(); defer { lock.unlock() }
            return (_outcome, _savedCount)
        }
    }

    /// Runs one encode and returns the reported outcome together with the save count at that moment.
    private func encode(_ image: UIImage,
                        properties: [String: Any]? = nil) -> (Result<Void, CaptureEventError>, Int) {
        let answered = expectation(description: "completion called")
        answered.assertForOverFulfill = true
        let answer = Answer()

        model.encodeAndProcess(image: image,
                               compressionQuality: 0.8,
                               properties: properties) { [weak self] result in
            answer.record(result, savedCount: self?.model.savedCount ?? -1)
            answered.fulfill()
        }

        wait(for: [answered], timeout: 5)
        let (outcome, savedCount) = answer.value
        guard let outcome else {
            XCTFail("The completion must report an outcome")
            return (.failure(.captureFailed), savedCount)
        }
        return (outcome, savedCount)
    }

    // MARK: - A capture requested off the main thread

    /// Records which thread the UIKit walk ran on, and stands in a real frame so the capture
    /// can complete without a foreground scene.
    private final class ThreadRecordingModel: SessionReplayModel {
        private let lock = NSLock()
        private var _preparedOnMain: Bool?

        var preparedOnMain: Bool? {
            lock.lock(); defer { lock.unlock() }; return _preparedOnMain
        }

        override func prepareCapturedFrameOnMain(properties: [String: Any]?) -> CapturedFrame? {
            lock.lock()
            _preparedOnMain = Thread.isMainThread
            lock.unlock()
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
            let image = renderer.image { ctx in
                UIColor.green.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
            return CapturedFrame(image: image, maskRects: [])
        }

        override func saveScreenshotToFileSystem(screenshotData: Data, properties: [String: Any]?) {}
    }

    /// An ANR span is built on the watchdog thread and `reportError` can be called from anywhere.
    /// The UIKit walk bails off-main, so a capture requested from a background queue used to drop
    /// without ever rendering — the frame was lost and the span carried no screenshot.
    func testCaptureRequestedOffMain_runsTheUIKitWalkOnMainAndStillShips() {
        // Needs options: the native path reads captureCompressionQuality off them to encode.
        let model = ThreadRecordingModel(sessionReplayOptions: SessionReplayOptions(recordingType: .image))
        let answered = expectation(description: "completion called")
        answered.assertForOverFulfill = true
        let answer = Answer()

        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread, "The request must start off the main thread")
            _ = model.captureAutomatic(properties: nil) { result in
                answer.record(result, savedCount: 0)
                answered.fulfill()
            }
        }

        wait(for: [answered], timeout: 5)
        XCTAssertEqual(model.preparedOnMain, true,
                       "The capture must be moved to the main thread, not dropped")
        guard case .success = answer.value.outcome else {
            XCTFail("An off-main request must still ship a frame, got \(String(describing: answer.value.outcome))")
            return
        }
    }

    // MARK: - A frame that ships

    func testCompletion_reportsSuccessAndSavesTheFrame() {
        let (outcome, saved) = encode(solidImage(red: 1.0))

        guard case .success = outcome else {
            XCTFail("A new frame must report success, got \(outcome)")
            return
        }
        XCTAssertEqual(saved, 1, "Reported success must mean the frame reached the save path")
    }

    // MARK: - A frame deduplicated away

    func testCompletion_reportsSkippingEventForAnIdenticalFrame() {
        let (first, savedAfterFirst) = encode(solidImage(red: 1.0))
        guard case .success = first else {
            XCTFail("The first frame must ship, got \(first)")
            return
        }
        XCTAssertEqual(savedAfterFirst, 1)

        // Same pixels: the skip-identical check drops it, and the caller must be told so it does
        // not stamp a span with a screenshot no frame will carry.
        let (second, savedAfterSecond) = encode(solidImage(red: 1.0))
        guard case .failure(let error) = second else {
            XCTFail("An identical frame must be dropped, got \(second)")
            return
        }
        XCTAssertEqual(error, .skippingEvent)
        XCTAssertEqual(savedAfterSecond, 1, "The deduplicated frame must not reach the save path")
    }

    func testCompletion_reportsSuccessForAChangedFrame() {
        _ = encode(solidImage(red: 1.0))

        let (outcome, saved) = encode(solidImage(red: 0.0))
        guard case .success = outcome else {
            XCTFail("A changed frame must ship, got \(outcome)")
            return
        }
        XCTAssertEqual(saved, 2, "A changed frame must reach the save path too")
    }

    // MARK: - A manual capture bypasses deduplication

    /// `CoralogixRum.captureEvent()` is public, returns void, and both demo apps drive it. Tapping
    /// it twice on a static screen used to drop the second frame, emit no span and log nothing,
    /// leaving the host no way to tell.
    func testCompletion_reportsSuccessForAnIdenticalManualFrame() {
        _ = encode(solidImage(red: 1.0))

        let (outcome, saved) = encode(solidImage(red: 1.0),
                                      properties: [Keys.isManual.rawValue: true])

        guard case .success = outcome else {
            XCTFail("A manual capture must ship even when the pixels are unchanged, got \(outcome)")
            return
        }
        XCTAssertEqual(saved, 2, "The manual frame must reach the save path despite identical pixels")
    }

    // MARK: - A click frame bypasses deduplication

    /// The tap marker is drawn downstream of the skip-identical check, so a tap on an unchanged
    /// screen would otherwise dedup away and lose its marker frame.
    func testCompletion_reportsSuccessForAnIdenticalClickFrame() {
        _ = encode(solidImage(red: 1.0))

        let clickProperties: [String: Any] = [
            Keys.positionX.rawValue: 10.0,
            Keys.positionY.rawValue: 20.0
        ]
        let (outcome, saved) = encode(solidImage(red: 1.0), properties: clickProperties)

        guard case .success = outcome else {
            XCTFail("A click frame must ship even when the pixels are unchanged, got \(outcome)")
            return
        }
        XCTAssertEqual(saved, 2, "The click frame must reach the save path despite identical pixels")
    }

    /// The exemption above is for the marker the pipeline is about to draw. A tap inside a
    /// masked region is never drawn — the pipeline suppresses it so a run of markers cannot
    /// reconstruct what was typed on a masked keypad — so that frame carries nothing new and
    /// is a genuine duplicate.
    func testCompletion_deduplicatesAnIdenticalClickFrameWhoseMarkerIsSuppressed() {
        _ = encode(solidImage(red: 1.0))

        let tapUnderAMask: [String: Any] = [
            Keys.positionX.rawValue: 10.0,
            Keys.positionY.rawValue: 20.0,
            Keys.maskRects.rawValue: [CGRect(x: 0, y: 0, width: 100, height: 100)]
        ]
        let (outcome, saved) = encode(solidImage(red: 1.0), properties: tapUnderAMask)

        guard case .failure(let error) = outcome else {
            XCTFail("A click frame with no marker to draw must deduplicate, got \(outcome)")
            return
        }
        XCTAssertEqual(error, .skippingEvent)
        XCTAssertEqual(saved, 1, "no second frame should reach the save path")
    }
}
