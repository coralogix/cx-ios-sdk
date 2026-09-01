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
    private class SaveCountingModel: SessionReplayModel {
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
                        properties: [String: Any]? = nil,
                        model: SaveCountingModel? = nil) -> (Result<Void, CaptureEventError>, Int) {
        let target = model ?? self.model!
        let answered = expectation(description: "completion called")
        answered.assertForOverFulfill = true
        let answer = Answer()

        target.encodeAndProcess(image: image,
                                compressionQuality: 0.8,
                                properties: properties) { result in
            answer.record(result, savedCount: target.savedCount)
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

    // MARK: - Only a frame that ships sets the baseline

    /// Fails the encode so the frame cannot ship, then offers the same pixels again. If the
    /// unshipped frame had become the comparison baseline, the retry would be read as a duplicate
    /// and the screen would never appear in the replay at all.
    private final class FailingEncodeModel: SessionReplayModel {
        var failNextEncode = true
        private let lock = NSLock()
        private var _savedCount = 0

        var savedCount: Int { lock.lock(); defer { lock.unlock() }; return _savedCount }

        override func jpegData(from image: UIImage, compressionQuality: CGFloat) -> Data? {
            if failNextEncode {
                failNextEncode = false
                return nil
            }
            return super.jpegData(from: image, compressionQuality: compressionQuality)
        }

        override func saveScreenshotToFileSystem(screenshotData: Data, properties: [String: Any]?) {
            lock.lock(); defer { lock.unlock() }; _savedCount += 1
        }
    }

    func testFailedEncode_doesNotBecomeTheDeduplicationBaseline() {
        let failing = FailingEncodeModel()
        let image = solidImage(red: 1.0)

        func run() -> Result<Void, CaptureEventError> {
            let answered = expectation(description: "completion called")
            let answer = Answer()
            failing.encodeAndProcess(image: image, compressionQuality: 0.8, properties: nil) { result in
                answer.record(result, savedCount: 0)
                answered.fulfill()
            }
            wait(for: [answered], timeout: 5)
            return answer.value.outcome ?? .failure(.captureFailed)
        }

        // First attempt cannot encode, so nothing ships. A fault, not a policy decision — the
        // frame was wanted and the encoder let us down, and a caller can tell the two apart.
        guard case .failure(let error) = run() else {
            XCTFail("A failed encode must report failure")
            return
        }
        XCTAssertEqual(error, .captureFailed,
                       "an encode failure is a fault, not an expected skip")
        XCTAssertEqual(failing.savedCount, 0)

        // Same pixels again, this time encodable. It has to ship: no frame for this screen has
        // reached the save path yet.
        guard case .success = run() else {
            XCTFail("The retry must ship — the failed frame never became the baseline")
            return
        }
        XCTAssertEqual(failing.savedCount, 1, "The retry must reach the save path")
    }

    /// A host-encoded frame ships without going through the comparison, so it has to release the
    /// baseline. Otherwise the next automatic capture is measured against the frame before it —
    /// and an unchanged-looking screen is dropped as a duplicate when the replay has in fact
    /// moved on and come back.
    func testCaptureManual_releasesTheDeduplicationBaseline() {
        let image = solidImage(red: 1.0)

        // An automatic frame ships and sets the baseline.
        let (first, savedAfterFirst) = encode(image)
        guard case .success = first else {
            XCTFail("The first frame must ship, got \(first)")
            return
        }
        XCTAssertEqual(savedAfterFirst, 1)

        // A host supplies its own encoded frame. It ships, and is now the last frame shown.
        model.captureManual(properties: nil, screenshotData: Data("host frame".utf8))

        // The same pixels as the first frame. The screen has changed twice since that frame, so
        // this has to ship — comparing it against the pre-manual baseline would drop it.
        let (third, _) = encode(image)
        guard case .success = third else {
            XCTFail("An automatic capture after a manual one must not be compared against the frame before it, got \(third)")
            return
        }
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
            Keys.nativeMaskRects.rawValue: [CGRect(x: 0, y: 0, width: 100, height: 100)]
        ]
        let (outcome, saved) = encode(solidImage(red: 1.0), properties: tapUnderAMask)

        guard case .failure(let error) = outcome else {
            XCTFail("A click frame with no marker to draw must deduplicate, got \(outcome)")
            return
        }
        XCTAssertEqual(error, .skippingEvent)
        XCTAssertEqual(saved, 1, "no second frame should reach the save path")
    }

    /// Dart reports every masked row behind a modal barrier, which unions to the whole screen.
    /// Read as "this tap landed on masked content", that removes the exemption from every tap
    /// taken while a Flutter dialog is open — a tap on the barrier, a disabled row or an already
    /// focused field would drop its frame and leave the interaction span pointing at nothing.
    /// Only the rects the capture pass painted itself decide this.
    func testCompletion_keepsAClickFrameWhenOnlyDartReportedTheTapAsMasked() {
        _ = encode(solidImage(red: 1.0))

        let tapWithADialogOpen: [String: Any] = [
            Keys.positionX.rawValue: 10.0,
            Keys.positionY.rawValue: 20.0,
            // What a Flutter dialog produces: the merged set covers the tap, the native set is empty.
            Keys.maskRects.rawValue: [CGRect(x: 0, y: 0, width: 1_000, height: 1_000)],
            Keys.nativeMaskRects.rawValue: [CGRect]()
        ]
        let (outcome, saved) = encode(solidImage(red: 1.0), properties: tapWithADialogOpen)

        guard case .success = outcome else {
            XCTFail("A tap must keep its frame when only Dart's over-report covers it, got \(outcome)")
            return
        }
        XCTAssertEqual(saved, 2, "the click frame must reach the save path")
    }

    /// A frame that ships sets the baseline the next one is measured against. If the baseline is
    /// released while that frame is still encoding — a session rotation, or a host frame shipped
    /// through `captureManual` — the release must win: reinstating the older fingerprint measures
    /// the next capture against a screen the replay has moved on from, and on an idle rotation,
    /// where nothing visibly changed, drops the new session's very first frame.
    func testCompletion_aBaselineReleasedMidEncodeIsNotReinstated() {
        let rotating = ReleaseDuringEncodeModel()

        // The first frame ships, and would normally become the baseline — but this model rotates
        // the session from inside its own encode, after the comparison has already run.
        _ = encode(solidImage(red: 1.0), model: rotating)
        rotating.releaseDuringEncode = false

        // An identical second frame must still ship: there is no baseline left to match it.
        let (outcome, saved) = encode(solidImage(red: 1.0), model: rotating)
        guard case .success = outcome else {
            XCTFail("The released baseline must not be reinstated by the in-flight encode, got \(outcome)")
            return
        }
        XCTAssertEqual(saved, 2, "both frames must reach the save path")
    }

    /// Releases the baseline from inside the JPEG encode — the window between the comparison and
    /// the commit. `jpegData(from:compressionQuality:)` is the seam the model exposes for exactly
    /// this kind of interleaving.
    private final class ReleaseDuringEncodeModel: SaveCountingModel {
        var releaseDuringEncode = true

        override func jpegData(from image: UIImage, compressionQuality: CGFloat) -> Data? {
            let data = super.jpegData(from: image, compressionQuality: compressionQuality)
            if releaseDuringEncode {
                // What a session rotation does, mid-encode.
                updateSessionId(with: "rotated-\(UUID().uuidString)")
            }
            return data
        }
    }
}
