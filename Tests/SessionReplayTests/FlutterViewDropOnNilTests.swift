//
//  FlutterViewDropOnNilTests.swift
//  Session-Replay-Tests
//
//  Drop-on-nil policy: when Dart answers with no bitmap the whole capture is dropped —
//  no black fill, and no frame carried over from an earlier cycle. Also covers the
//  ordering guards: a late out-of-order delivery is dropped rather than shipped behind
//  the newer frame, and a session rotation both bumps the frame generation and releases
//  the accepted-frameId watermark for the new session.
//

import XCTest
import UIKit
import CoralogixInternal
@testable import SessionReplay

final class FlutterViewDropOnNilTests: XCTestCase {

    private var model: SessionReplayModel!

    override func setUp() {
        super.setUp()
        model = SessionReplayModel()
    }

    override func tearDown() {
        model = nil
        super.tearDown()
    }

    // MARK: - Helpers

    // Solid-color opaque RGBA bitmap.
    private func solidBitmap(width: Int, height: Int,
                             r: UInt8, g: UInt8, b: UInt8,
                             maskRects: [CGRect] = []) throws -> FlutterViewBitmap {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            bytes.append(contentsOf: [r, g, b, 255])
        }
        return try XCTUnwrap(FlutterViewBitmap(bytes: Data(bytes), width: width, height: height,
                                               maskRects: maskRects))
    }

    // Samples the image's color from a 1x1 render.
    private func sampledColor(of image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: bitmapInfo) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    // Unwraps a composited delivery, failing the test on any other outcome.
    private func composited(_ bitmap: FlutterViewBitmap?, frameId: Int64,
                            generation: Int64? = nil) throws -> SessionReplayModel.FlutterFrame {
        let outcome = model.acceptFlutterDelivery(freshBitmap: bitmap, frameId: frameId,
                                                 requestGeneration: generation ?? model.flutterFrameGeneration)
        guard case .composite(let frame) = outcome else {
            XCTFail("Expected .composite but got \(outcome)")
            throw XCTSkip("not composited")
        }
        return frame
    }

    // Asserts the delivery was dropped, and says whether the screenshot index goes back.
    private func assertDropped(_ bitmap: FlutterViewBitmap?, frameId: Int64,
                               generation: Int64? = nil,
                               expectStaleSession: Bool = false,
                               _ message: String) {
        let outcome = model.acceptFlutterDelivery(freshBitmap: bitmap, frameId: frameId,
                                                 requestGeneration: generation ?? model.flutterFrameGeneration)
        switch outcome {
        case .composite:
            XCTFail(message)
        case .staleSession:
            XCTAssertTrue(expectStaleSession, "\(message) — expected noFrame, got staleSession")
        case .noFrame:
            XCTAssertFalse(expectStaleSession, "\(message) — expected staleSession, got noFrame")
        }
    }

    // MARK: - A delivered bitmap is composited

    func testDeliveredBitmap_isComposited() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)

        let frame = try composited(red, frameId: 1)
        XCTAssertEqual(frame.image.width, 2)
        XCTAssertEqual(frame.image.height, 2)

        let color = try XCTUnwrap(sampledColor(of: frame.image))
        XCTAssertEqual(color.r, 255, "The composited frame must carry the delivered pixels")
        XCTAssertEqual(color.g, 0)
        XCTAssertEqual(color.b, 0)
    }

    func testDeliveredBitmap_carriesItsOwnMaskRects() throws {
        let rects = [CGRect(x: 1, y: 2, width: 3, height: 4)]
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0, maskRects: rects)

        let frame = try composited(red, frameId: 1)
        XCTAssertEqual(frame.maskRects, rects,
                       "Mask geometry must travel with the pixels it was composited into")
    }

    // MARK: - Drop on nil

    func testNilDelivery_dropsCapture() {
        assertDropped(nil, frameId: 1,
                      "With no bitmap the capture must be dropped, never black-filled")
    }

    /// The regression this policy exists for: a nil after a good frame used to composite the
    /// cached frame, shipping stale pixels under a fresh timestamp.
    func testNilDelivery_afterAGoodFrame_stillDropsInsteadOfReusingIt() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        _ = try composited(red, frameId: 1)

        assertDropped(nil, frameId: 2,
                      "A nil delivery must drop the capture, not reuse the previous frame")
        assertDropped(nil, frameId: 3,
                      "Every subsequent nil must keep dropping — nothing is held")
    }

    // MARK: - Ordering guards

    func testOutOfOrderDelivery_isDropped() throws {
        let green = try solidBitmap(width: 2, height: 2, r: 0, g: 255, b: 0)
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)

        let newer = try composited(green, frameId: 5)
        let color = try XCTUnwrap(sampledColor(of: newer.image))
        XCTAssertEqual(color.g, 255)

        assertDropped(red, frameId: 3,
                      "A delivery older than one already composited must be dropped, not shipped behind it")
    }

    func testRepeatedFrameId_isDropped() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        _ = try composited(red, frameId: 7)

        assertDropped(red, frameId: 7,
                      "A second delivery for an already-composited frameId must be dropped")
    }

    func testNewerDelivery_isComposited() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        let green = try solidBitmap(width: 2, height: 2, r: 0, g: 255, b: 0)

        _ = try composited(red, frameId: 1)
        let latest = try composited(green, frameId: 2)

        let color = try XCTUnwrap(sampledColor(of: latest.image))
        XCTAssertEqual(color.g, 255, "The newest delivery's pixels must be the ones composited")
        XCTAssertEqual(color.r, 0)
    }

    // MARK: - Session rotation

    func testSessionRotation_releasesTheAcceptedFrameIdWatermark() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        _ = try composited(red, frameId: 9)

        model.updateSessionId(with: "new-session-\(UUID().uuidString)")

        // The frame counter is not per-session, but the watermark is: a lower frameId in the
        // new session must still be composited rather than read as out-of-order.
        _ = try composited(red, frameId: 2)
    }

    func testSessionRotation_bumpsFlutterFrameGeneration() {
        // A callback captures the generation before its Dart round-trip; if a rotation
        // happens meanwhile the generation differs, so the callback is discarded.
        let gen0 = model.flutterFrameGeneration
        model.updateSessionId(with: "session-A")
        let genA = model.flutterFrameGeneration
        XCTAssertNotEqual(genA, gen0,
                          "A session change must bump the generation so pre-rotation callbacks read as stale")

        // Re-setting the same id is not a rotation — must not bump.
        model.updateSessionId(with: "session-A")
        XCTAssertEqual(model.flutterFrameGeneration, genA,
                       "Re-setting the same session id must not bump the generation")

        model.updateSessionId(with: "session-B")
        XCTAssertNotEqual(model.flutterFrameGeneration, genA, "A second rotation must bump again")
    }

    // MARK: - Rotation is atomic with acceptance

    /// The generation check and the watermark test share one critical section. Read separately, a
    /// rotation landing between them lets a pre-rotation bitmap pass both and reach the new
    /// session — the leak the generation guard exists to prevent.
    func testDeliveryFromAPreviousSession_isDroppedWithoutReturningTheIndex() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        let generationAtRequest = model.flutterFrameGeneration

        model.updateSessionId(with: "rotated-\(UUID().uuidString)")

        assertDropped(red, frameId: 1, generation: generationAtRequest, expectStaleSession: true,
                      "A delivery requested before the rotation must not reach the new session")
    }

    func testRotationBetweenRequestAndDelivery_isNotMaskedByTheWatermarkReset() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        let generationAtRequest = model.flutterFrameGeneration
        _ = try composited(red, frameId: 9, generation: generationAtRequest)

        // The rotation resets the watermark to 0, so frameId 9 would clear the watermark test on
        // its own. Only the generation, checked in the same critical section, still rejects it.
        model.updateSessionId(with: "rotated-\(UUID().uuidString)")

        assertDropped(red, frameId: 9, generation: generationAtRequest, expectStaleSession: true,
                      "A reset watermark must not let a pre-rotation delivery back in")
    }

    // MARK: - One delivery per cycle

    func testDeliveryGate_admitsTheFirstCallerOnly() {
        let gate = SessionReplayModel.FlutterDeliveryGate()
        XCTAssertTrue(gate.claim(), "The first delivery must be admitted")
        XCTAssertFalse(gate.claim(), "A second delivery for the same cycle must be refused")
        XCTAssertFalse(gate.claim(), "And every one after it")
    }

    /// A provider is host-app code and may break the main-thread contract. Exactly one concurrent
    /// caller may win, or the capture composites twice and reports its outcome twice.
    func testDeliveryGate_admitsOneCallerUnderConcurrency() {
        let gate = SessionReplayModel.FlutterDeliveryGate()
        let admitted = NSLock()
        var admittedCount = 0

        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if gate.claim() {
                admitted.lock()
                admittedCount += 1
                admitted.unlock()
            }
        }

        XCTAssertEqual(admittedCount, 1, "Exactly one concurrent delivery may be admitted")
    }

    // MARK: - Tap context handed to the provider

    func testTapTimestamp_isConvertedToMilliseconds() throws {
        let seconds = 1_767_225_600.123
        let properties: [String: Any] = [Keys.timestamp.rawValue: seconds]

        let ms = try XCTUnwrap(model.tapTimestampMilliseconds(from: properties, isClick: true))
        XCTAssertEqual(ms, 1_767_225_600_123,
                       "Dart measures tap staleness in ms; seconds would read as hours stale")
    }

    func testTapTimestamp_isNilForAPeriodicCapture() {
        let properties: [String: Any] = [Keys.timestamp.rawValue: 1_767_225_600.0]
        XCTAssertNil(model.tapTimestampMilliseconds(from: properties, isClick: false),
                     "Only a click capture carries a tap timestamp")
    }

    func testTapTimestamp_isNilWhenTheCaptureCarriesNone() {
        // getTimestamp's fallback is already in milliseconds while its stored value is in
        // seconds, so converting it would hand Dart microseconds — a tap dated far in the future.
        XCTAssertNil(model.tapTimestampMilliseconds(from: [:], isClick: true),
                     "A click with no timestamp must omit the value, not synthesise one")
        XCTAssertNil(model.tapTimestampMilliseconds(from: nil, isClick: true),
                     "Nil properties must omit the value too")
    }

    func testTapTimestamp_isNilForANonFiniteTimestamp() {
        let properties: [String: Any] = [Keys.timestamp.rawValue: Double.nan]
        XCTAssertNil(model.tapTimestampMilliseconds(from: properties, isClick: true),
                     "A NaN timestamp from a hybrid bridge must yield nil, not trap")
    }
}
