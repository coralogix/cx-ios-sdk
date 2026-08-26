//
//  FlutterViewHoldLastFrameTests.swift
//  Session-Replay-Tests
//
//  Hold-last-frame policy: a nil bitmap must never black-fill — reuse the last
//  frame, or skip if none delivered yet. Also guards against stale frames: an
//  out-of-order (older) delivery must not overwrite a newer one, and a session
//  rotation must bump the frame generation so pre-rotation callbacks read as stale.
//

import XCTest
import UIKit
import CoralogixInternal
@testable import SessionReplay

final class FlutterViewHoldLastFrameTests: XCTestCase {

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

    // MARK: - Hold last frame

    func testProviderReturnsNilAfterValidFrame_reusesLastDeliveredFrame() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)

        let delivered = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(red), frameId: 1),
                                      "A valid bitmap must render to a CGImage")
        XCTAssertEqual(delivered.image.width, 2)
        XCTAssertEqual(delivered.image.height, 2)

        // Provider returns no frame.
        let held = try XCTUnwrap(model.resolveFlutterFrame(response: .unavailable, frameId: 2),
                                 "A nil bitmap must reuse the last delivered frame, not skip")
        XCTAssertTrue(held.image === delivered.image,
                      "The held frame must be the exact last delivered CGImage")

        let color = try XCTUnwrap(sampledColor(of: held.image))
        XCTAssertEqual(color.r, 255, "Held frame must preserve the delivered red content")
        XCTAssertEqual(color.g, 0)
        XCTAssertEqual(color.b, 0)
        // A black-fill regression would make this (0,0,0).
        XCTAssertFalse(color.r == 0 && color.g == 0 && color.b == 0,
                       "Held frame must not be black")
    }

    func testNoPriorFrame_skips_thenHoldsOnceDelivered() throws {
        // No frame yet: nil must skip, not black-fill.
        XCTAssertNil(model.resolveFlutterFrame(response: .unavailable, frameId: 1),
                     "With no delivered frame the capture must be skipped, never black-filled")

        // After a delivery, a later nil holds it.
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        _ = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(red), frameId: 2))
        XCTAssertNotNil(model.resolveFlutterFrame(response: .unavailable, frameId: 3),
                        "After a frame is delivered, a nil result must hold it (non-nil)")
    }

    func testNewDelivery_replacesHeldFrame() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        let green = try solidBitmap(width: 2, height: 2, r: 0, g: 255, b: 0)

        _ = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(red), frameId: 1))
        let latest = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(green), frameId: 2))

        // nil reuses the latest (green), not the old red.
        let held = try XCTUnwrap(model.resolveFlutterFrame(response: .unavailable, frameId: 3))
        XCTAssertTrue(held.image === latest.image, "Held frame must be the most recent delivery")

        let color = try XCTUnwrap(sampledColor(of: held.image))
        XCTAssertEqual(color.g, 255, "Held frame must be the most recent (green) delivery")
        XCTAssertEqual(color.r, 0)
        XCTAssertEqual(color.b, 0)
    }

    // MARK: - Staleness guards

    func testOutOfOrderFrame_doesNotOverwriteNewerCachedFrame() throws {
        let green = try solidBitmap(width: 2, height: 2, r: 0, g: 255, b: 0)
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)

        // Newer frame (id 5) is cached.
        let newer = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(green), frameId: 5))

        // Out-of-order older delivery (id 3) must be ignored — return the newer cached frame.
        let outOfOrder = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(red), frameId: 3))
        XCTAssertTrue(outOfOrder.image === newer.image, "An older frameId must not overwrite the newer cached frame")

        let color = try XCTUnwrap(sampledColor(of: outOfOrder.image))
        XCTAssertEqual(color.g, 255, "Cache must still hold the newer (green) frame")
        XCTAssertEqual(color.r, 0)

        // A later nil also reuses green, confirming red was never cached.
        let held = try XCTUnwrap(model.resolveFlutterFrame(response: .unavailable, frameId: 6))
        XCTAssertTrue(held.image === newer.image, "The stale red frame must never surface")
    }

    // MARK: - Mask rects travel with their bitmap

    /// A reused stale bitmap must carry the rects of *its* frame. Caching the rects apart
    /// from the image would pair reused pixels with fresh geometry — the pixels/metadata
    /// disagreement the rects exist to prevent.
    func testHeldFrame_carriesItsOwnMaskRects() throws {
        let redRects = [CGRect(x: 1, y: 2, width: 3, height: 4)]
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0, maskRects: redRects)

        _ = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(red), frameId: 1))

        // Provider returns no frame — the held bitmap must come back with the rects it
        // was delivered with.
        let held = try XCTUnwrap(model.resolveFlutterFrame(response: .unavailable, frameId: 2))
        XCTAssertEqual(held.maskRects, redRects,
                       "A held frame must carry the mask rects of its own delivery")
    }

    func testOutOfOrderFrame_doesNotPairCachedImageWithItsRects() throws {
        let greenRects = [CGRect(x: 10, y: 10, width: 5, height: 5)]
        let redRects = [CGRect(x: 90, y: 90, width: 5, height: 5)]
        let green = try solidBitmap(width: 2, height: 2, r: 0, g: 255, b: 0, maskRects: greenRects)
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0, maskRects: redRects)

        let newer = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(green), frameId: 5))

        // The stale delivery is rejected whole: the cached green image keeps green's rects,
        // and red's rects never attach to it.
        let outOfOrder = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(red), frameId: 3))
        XCTAssertTrue(outOfOrder.image === newer.image)
        XCTAssertEqual(outOfOrder.maskRects, greenRects,
                       "The cached frame's rects must be its own, never a rejected delivery's")
    }

    func testSessionChange_clearsHeldFrame() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        _ = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(red), frameId: 1))

        // Session change must drop the held frame.
        model.updateSessionId(with: "new-session-\(UUID().uuidString)")

        XCTAssertNil(model.resolveFlutterFrame(response: .unavailable, frameId: 2),
                     "A new session must not reuse the previous session's held frame")
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

    // MARK: - One-Frame Rule (skip-not-stale)

    func testSkipResponse_dropsEvenWithCachedFrame() throws {
        // .skip is the plugin's deliberate "no frame this tick" — substituting the
        // cache here is exactly the stale-frame bug the response enum exists to kill.
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        _ = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(red), frameId: 1))

        XCTAssertNil(model.resolveFlutterFrame(response: .skip, frameId: 2),
                     ".skip must drop the frame even when a cached frame exists")
        XCTAssertNil(model.resolveFlutterFrame(response: .skip, frameId: 3, isClick: true),
                     ".skip must drop click frames too")
    }

    func testUnavailableClickFrame_dropsInsteadOfReusingCache() throws {
        // A fresh tap marker must never be baked into old pixels: marker suppression
        // would run against the old frame's mask rects (masked-keypad reconstruction).
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        _ = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(red), frameId: 1))

        XCTAssertNil(model.resolveFlutterFrame(response: .unavailable, frameId: 2, isClick: true),
                     "A click frame with no fresh bitmap must drop, never reuse the cache")
        XCTAssertNotNil(model.resolveFlutterFrame(response: .unavailable, frameId: 3),
                        "Periodic captures keep the legacy cache-reuse fallback")
    }

    func testOutOfOrderClickDelivery_dropsInsteadOfReusingCache() throws {
        // An older-frameId delivery for a click is stale by definition under the
        // One-Frame Rule — reusing the newest cached frame would pair the marker
        // with pixels from a different instant.
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        let green = try solidBitmap(width: 2, height: 2, r: 0, g: 255, b: 0)
        _ = try XCTUnwrap(model.resolveFlutterFrame(response: .frame(green), frameId: 5))

        XCTAssertNil(model.resolveFlutterFrame(response: .frame(red), frameId: 3, isClick: true),
                     "An out-of-order click delivery must drop, not fall back to the cache")
    }
}
