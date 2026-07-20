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
                             r: UInt8, g: UInt8, b: UInt8) throws -> FlutterViewBitmap {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            bytes.append(contentsOf: [r, g, b, 255])
        }
        return try XCTUnwrap(FlutterViewBitmap(bytes: Data(bytes), width: width, height: height))
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

        let delivered = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: red, frameId: 1),
                                      "A valid bitmap must render to a CGImage")
        XCTAssertEqual(delivered.width, 2)
        XCTAssertEqual(delivered.height, 2)

        // Provider returns no frame.
        let held = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: nil, frameId: 2),
                                 "A nil bitmap must reuse the last delivered frame, not skip")
        XCTAssertTrue(held === delivered,
                      "The held frame must be the exact last delivered CGImage")

        let color = try XCTUnwrap(sampledColor(of: held))
        XCTAssertEqual(color.r, 255, "Held frame must preserve the delivered red content")
        XCTAssertEqual(color.g, 0)
        XCTAssertEqual(color.b, 0)
        // A black-fill regression would make this (0,0,0).
        XCTAssertFalse(color.r == 0 && color.g == 0 && color.b == 0,
                       "Held frame must not be black")
    }

    func testNoPriorFrame_skips_thenHoldsOnceDelivered() throws {
        // No frame yet: nil must skip, not black-fill.
        XCTAssertNil(model.resolveFlutterCGImage(freshBitmap: nil, frameId: 1),
                     "With no delivered frame the capture must be skipped, never black-filled")

        // After a delivery, a later nil holds it.
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        _ = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: red, frameId: 2))
        XCTAssertNotNil(model.resolveFlutterCGImage(freshBitmap: nil, frameId: 3),
                        "After a frame is delivered, a nil result must hold it (non-nil)")
    }

    func testNewDelivery_replacesHeldFrame() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        let green = try solidBitmap(width: 2, height: 2, r: 0, g: 255, b: 0)

        _ = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: red, frameId: 1))
        let latest = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: green, frameId: 2))

        // nil reuses the latest (green), not the old red.
        let held = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: nil, frameId: 3))
        XCTAssertTrue(held === latest, "Held frame must be the most recent delivery")

        let color = try XCTUnwrap(sampledColor(of: held))
        XCTAssertEqual(color.g, 255, "Held frame must be the most recent (green) delivery")
        XCTAssertEqual(color.r, 0)
        XCTAssertEqual(color.b, 0)
    }

    // MARK: - Staleness guards

    func testOutOfOrderFrame_doesNotOverwriteNewerCachedFrame() throws {
        let green = try solidBitmap(width: 2, height: 2, r: 0, g: 255, b: 0)
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)

        // Newer frame (id 5) is cached.
        let newer = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: green, frameId: 5))

        // Out-of-order older delivery (id 3) must be ignored — return the newer cached frame.
        let outOfOrder = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: red, frameId: 3))
        XCTAssertTrue(outOfOrder === newer, "An older frameId must not overwrite the newer cached frame")

        let color = try XCTUnwrap(sampledColor(of: outOfOrder))
        XCTAssertEqual(color.g, 255, "Cache must still hold the newer (green) frame")
        XCTAssertEqual(color.r, 0)

        // A later nil also reuses green, confirming red was never cached.
        let held = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: nil, frameId: 6))
        XCTAssertTrue(held === newer, "The stale red frame must never surface")
    }

    func testSessionChange_clearsHeldFrame() throws {
        let red = try solidBitmap(width: 2, height: 2, r: 255, g: 0, b: 0)
        _ = try XCTUnwrap(model.resolveFlutterCGImage(freshBitmap: red, frameId: 1))

        // Session change must drop the held frame.
        model.updateSessionId(with: "new-session-\(UUID().uuidString)")

        XCTAssertNil(model.resolveFlutterCGImage(freshBitmap: nil, frameId: 2),
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
}
