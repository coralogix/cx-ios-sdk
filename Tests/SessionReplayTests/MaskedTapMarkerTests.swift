//
//  MaskedTapMarkerTests.swift
//  SessionReplayTests
//

import XCTest
import UIKit
import CoreImage
import CoralogixInternal
@testable import SessionReplay

/// A tap landing inside a region this frame masked must draw no marker: the marker would reveal
/// which element under the mask was hit, and a run of markers reconstructs what was entered on a
/// masked keypad. The frame itself is still recorded.
final class MaskedTapMarkerTests: XCTestCase {

    private let ciContext = CIContext()

    // MARK: - Helpers

    /// Plain white frame — any pixel difference in these tests is the click marker and nothing
    /// else, since no masking or scanner stage is enabled.
    private func makeBlankFrameData(size: CGSize = CGSize(width: 400, height: 400)) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }.pngData()!
    }

    private func makeEntry(data: Data, point: CGPoint?, maskRects: [CGRect]) -> URLEntry {
        URLEntry(url: URL(fileURLWithPath: "/tmp/masked_tap_marker_test.png"),
                 timestamp: 0,
                 screenshotId: "test-screenshot-id",
                 segmentIndex: 0,
                 page: "0",
                 screenshotData: data,
                 point: point,
                 containsSwiftUIContent: false,
                 maskRects: maskRects,
                 completion: nil)
    }

    /// All scanner stages off, so the click stage is the only one that can alter the frame.
    private func makeOptions() -> SessionReplayOptions {
        SessionReplayOptions(maskText: nil, maskOnlyCreditCards: false, maskAllImages: false)
    }

    private func pngBytes(_ image: CIImage) -> Data? {
        ciContext.pngRepresentation(of: image,
                                    format: .RGBA8,
                                    colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    private func runPipeline(entry: URLEntry) -> CIImage? {
        let expectation = self.expectation(description: "pipeline completes")
        var result: CIImage?
        ScannerPipeline().runPipeline(options: makeOptions(), urlEntry: entry) { ciImage, _ in
            result = ciImage
            expectation.fulfill()
        }
        waitForExpectations(timeout: 30, handler: nil)
        return result
    }

    // MARK: - Tests

    func testTapInsideMaskedRegion_drawsNoMarker() {
        let data = makeBlankFrameData()
        let entry = makeEntry(data: data,
                              point: CGPoint(x: 100, y: 100),
                              maskRects: [CGRect(x: 50, y: 50, width: 150, height: 150)])

        guard let output = runPipeline(entry: entry) else {
            XCTFail("Pipeline returned nil image")
            return
        }

        XCTAssertEqual(pngBytes(output), pngBytes(CIImage(data: data)!),
                       "A tap inside a masked region must leave the frame untouched")
    }

    func testTapOutsideMaskedRegion_drawsMarker() {
        let data = makeBlankFrameData()
        let entry = makeEntry(data: data,
                              point: CGPoint(x: 300, y: 300),
                              maskRects: [CGRect(x: 50, y: 50, width: 150, height: 150)])

        guard let output = runPipeline(entry: entry) else {
            XCTFail("Pipeline returned nil image")
            return
        }

        XCTAssertNotEqual(pngBytes(output), pngBytes(CIImage(data: data)!),
                          "A tap outside every masked region must still draw its marker")
    }

    /// Guards the suppression from swallowing the ordinary case: a frame that masked nothing must
    /// keep drawing markers exactly as before.
    func testTapOnUnmaskedFrame_drawsMarker() {
        let data = makeBlankFrameData()
        let entry = makeEntry(data: data, point: CGPoint(x: 100, y: 100), maskRects: [])

        guard let output = runPipeline(entry: entry) else {
            XCTFail("Pipeline returned nil image")
            return
        }

        XCTAssertNotEqual(pngBytes(output), pngBytes(CIImage(data: data)!),
                          "With no masked regions the marker must be drawn")
    }

    // MARK: - containsTap

    func testContainsTap_pointInsideRect() {
        let rects = [CGRect(x: 20, y: 40, width: 200, height: 160)]

        XCTAssertTrue(rects.containsTap(CGPoint(x: 100, y: 100)))
    }

    func testContainsTap_pointOutsideRect() {
        let rects = [CGRect(x: 20, y: 40, width: 200, height: 160)]

        XCTAssertFalse(rects.containsTap(CGPoint(x: 250, y: 100)),
                       "A tap to the right of the only masked region is not masked")
        XCTAssertFalse(rects.containsTap(CGPoint(x: 100, y: 10)),
                       "A tap above the only masked region is not masked")
    }

    func testContainsTap_noRects() {
        XCTAssertFalse([CGRect]().containsTap(CGPoint(x: 100, y: 100)),
                       "A frame that masked nothing suppresses no markers")
    }

    /// Fails closed across layers: it is enough for any one region to contain the tap.
    func testContainsTap_matchesAnyRectInAMultiRectFrame() {
        let rects = [
            CGRect(x: 0, y: 0, width: 50, height: 50),
            CGRect(x: 200, y: 300, width: 80, height: 80),
            CGRect(x: 100, y: 100, width: 20, height: 20)
        ]

        XCTAssertTrue(rects.containsTap(CGPoint(x: 240, y: 340)),
                      "A tap inside the second region must count")
        XCTAssertFalse(rects.containsTap(CGPoint(x: 160, y: 160)),
                       "A tap in the gap between regions must not count")
    }

    // MARK: - Multi-region frames

    /// Fails closed across layers — a tap inside any one of the frame's regions is suppressed.
    func testTapInsideSecondOfSeveralMaskedRegions_drawsNoMarker() {
        let data = makeBlankFrameData()
        let entry = makeEntry(data: data,
                              point: CGPoint(x: 320, y: 320),
                              maskRects: [CGRect(x: 10, y: 10, width: 40, height: 40),
                                          CGRect(x: 300, y: 300, width: 60, height: 60)])

        guard let output = runPipeline(entry: entry) else {
            XCTFail("Pipeline returned nil image")
            return
        }

        XCTAssertEqual(pngBytes(output), pngBytes(CIImage(data: data)!),
                       "Any masked region containing the tap must suppress the marker")
    }
}
