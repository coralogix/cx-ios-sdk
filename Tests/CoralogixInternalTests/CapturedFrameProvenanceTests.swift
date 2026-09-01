//
//  CapturedFrameProvenanceTests.swift
//  CoralogixInternalTests
//
//  A captured frame's mask rects come from two places, and two decisions downstream need to
//  tell them apart: what may be repainted, and what may drop a frame. These pin the split so
//  a caller cannot silently get Dart's whole-screen over-report where it wanted its own rects.
//

import XCTest
import UIKit
@testable import CoralogixInternal

final class CapturedFrameProvenanceTests: XCTestCase {

    private let image = UIImage()

    func testNativeRectsDefaultToAllOfThem() {
        let rects = [CGRect(x: 0, y: 0, width: 10, height: 10)]

        let frame = CapturedFrame(image: image, maskRects: rects)

        XCTAssertEqual(frame.nativeMaskRects, rects,
                       "a frame assembled with no Dart bitmap has no other provenance to split out")
    }

    func testNativeRectsAreTheSubsetTheCapturePassPainted() {
        let native = [CGRect(x: 0, y: 0, width: 10, height: 10)]
        // What a Flutter dialog produces: every masked row behind the barrier.
        let fromDart = [CGRect(x: 0, y: 0, width: 1_000, height: 1_000)]

        let frame = CapturedFrame(image: image,
                                  maskRects: native + fromDart,
                                  nativeMaskRects: native)

        XCTAssertEqual(frame.maskRects.count, 2,
                       "tap-marker suppression asks about every masked region, whoever masked it")
        XCTAssertEqual(frame.nativeMaskRects, native,
                       "the deduplication decision must see only what this pass painted")
    }
}
