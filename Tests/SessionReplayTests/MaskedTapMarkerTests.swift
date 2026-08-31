//
//  MaskedTapMarkerTests.swift
//  SessionReplayTests
//

import XCTest
import UIKit
import CoreImage
@testable import CoralogixInternal
@testable import SessionReplay

/// Stands in for Flutter's own view class. `UIView.subtreeContainsFlutterView` resolves
/// `FlutterView` by Objective-C name, so a class registered under that name routes a window down
/// the capture pass's Flutter branch without linking Flutter into the test bundle.
@objc(FlutterView)
final class StubFlutterView: UIView {}

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

    // MARK: - Flutter fallback black fill

    // A window hosting a FlutterView with no Dart bitmap to paste is blacked out wholesale. That
    // region is masking like any other: it has to reach `CapturedFrame.maskRects`, or the marker
    // stage never tests taps against it and a marker lands on the black fill — revealing where
    // inside the hidden Flutter content the user touched.

    private var flutterScreen: CGRect { CGRect(x: 0, y: 0, width: 400, height: 400) }

    /// `captureFrame` walks visible windows only, so the window has to be unhidden — the capture
    /// never draws it (the Flutter branch blacks it out instead), it only has to pass the filter.
    private func makeFlutterWindow() -> UIWindow {
        let window = UIWindow(frame: flutterScreen)
        window.addSubview(StubFlutterView(frame: flutterScreen))
        window.isHidden = false
        addTeardownBlock { window.isHidden = true }
        return window
    }

    private func captureFlutterFallbackFrame(flutterViewRect: CGRect?) -> CapturedFrame {
        UIView().captureFrame(in: [makeFlutterWindow()],
                              bounds: flutterScreen,
                              scale: 1,
                              maskText: nil,
                              maskAllImages: false,
                              flutterCGImage: nil,
                              flutterViewRect: flutterViewRect,
                              flutterMaskRects: [])
    }

    func testFlutterFallbackWithNoReportedRect_masksTheWholeWindow() {
        let frame = captureFlutterFallbackFrame(flutterViewRect: nil)

        XCTAssertEqual(frame.maskRects, [flutterScreen],
                       "Blacking out the window must report the window as masked geometry")
    }

    func testFlutterFallbackWithReportedRect_masksThatRegion() {
        let region = CGRect(x: 50, y: 50, width: 150, height: 150)

        let frame = captureFlutterFallbackFrame(flutterViewRect: region)

        XCTAssertEqual(frame.maskRects, [region],
                       "The blacked-out Flutter region must be the reported mask geometry")
    }

    /// The fill covers a whole window, so it has to be painted as that window is composited —
    /// a window above it (a keyboard, an alert) draws after and must survive. Deferring the fill
    /// to the end of the pass instead blacks the higher window out; Android hit exactly that
    /// regression and fixed it the same way.
    func testWindowAboveTheFlutterFallback_isNotBlackedOut() {
        let alertWindow = UIWindow(frame: flutterScreen)
        alertWindow.windowLevel = .alert
        alertWindow.backgroundColor = .red
        alertWindow.isHidden = false
        addTeardownBlock { alertWindow.isHidden = true }

        let captured = UIView().captureFrame(in: [makeFlutterWindow(), alertWindow],
                                             bounds: flutterScreen,
                                             scale: 1,
                                             maskText: nil,
                                             maskAllImages: false,
                                             flutterCGImage: nil,
                                             flutterViewRect: nil,
                                             flutterMaskRects: [])

        XCTAssertTrue(containsRedPixel(captured.image),
                      "The window above the Flutter fallback must paint over the black fill")
        XCTAssertEqual(captured.maskRects, [flutterScreen],
                       "Painting it inline must not cost the frame its mask geometry")
    }

    /// Scans the whole frame rather than sampling a point, so the assertion does not depend on
    /// how CoreGraphics orients the bitmap.
    private func containsRedPixel(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).contains {
            pixels[$0] > 200 && pixels[$0 + 1] < 60 && pixels[$0 + 2] < 60
        }
    }

    func testTapInsideBlackFilledFlutterRegion_drawsNoMarker() {
        let region = CGRect(x: 50, y: 50, width: 150, height: 150)
        let captured = captureFlutterFallbackFrame(flutterViewRect: region)
        guard let data = captured.image.pngData() else {
            XCTFail("Captured frame produced no PNG data")
            return
        }
        let entry = makeEntry(data: data, point: CGPoint(x: 100, y: 100), maskRects: captured.maskRects)

        guard let output = runPipeline(entry: entry) else {
            XCTFail("Pipeline returned nil image")
            return
        }

        XCTAssertEqual(pngBytes(output), pngBytes(CIImage(data: data)!),
                       "A tap inside the blacked-out Flutter region must draw no marker")
    }

    func testTapOutsideBlackFilledFlutterRegion_drawsMarker() {
        let region = CGRect(x: 50, y: 50, width: 150, height: 150)
        let captured = captureFlutterFallbackFrame(flutterViewRect: region)
        guard let data = captured.image.pngData() else {
            XCTFail("Captured frame produced no PNG data")
            return
        }
        let entry = makeEntry(data: data, point: CGPoint(x: 300, y: 300), maskRects: captured.maskRects)

        guard let output = runPipeline(entry: entry) else {
            XCTFail("Pipeline returned nil image")
            return
        }

        XCTAssertNotEqual(pngBytes(output), pngBytes(CIImage(data: data)!),
                          "A tap outside the blacked-out Flutter region must still draw its marker")
    }

    // MARK: - Dart-reported mask rects

    // The plugin reports the rects it masked inside its own bitmap, and the host offsets them
    // into screen space. The geometry must not claim more than the pixels it describes: these
    // rects are painted as well as tested, so an oversized one blacks out native content outside
    // the Flutter view and suppresses markers there too.

    private func captureFlutterFrame(flutterViewRect: CGRect,
                                     flutterMaskRects: [CGRect]) throws -> CapturedFrame {
        let bitmap = UIGraphicsImageRenderer(size: flutterViewRect.size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: flutterViewRect.size))
        }
        return UIView().captureFrame(in: [makeFlutterWindow()],
                                     bounds: flutterScreen,
                                     scale: 1,
                                     maskText: nil,
                                     maskAllImages: false,
                                     flutterCGImage: try XCTUnwrap(bitmap.cgImage),
                                     flutterViewRect: flutterViewRect,
                                     flutterMaskRects: flutterMaskRects)
    }

    func testDartReportedRect_isOffsetIntoScreenSpace() throws {
        let frame = try captureFlutterFrame(flutterViewRect: CGRect(x: 40, y: 60, width: 200, height: 200),
                                            flutterMaskRects: [CGRect(x: 10, y: 20, width: 30, height: 40)])

        XCTAssertEqual(frame.maskRects, [CGRect(x: 50, y: 80, width: 30, height: 40)],
                       "A Flutter-view-local rect must be reported at its position on screen")
    }

    func testDartReportedRect_reachingBeyondTheBitmap_isClippedToIt() throws {
        let frame = try captureFlutterFrame(flutterViewRect: CGRect(x: 40, y: 60, width: 200, height: 200),
                                            flutterMaskRects: [CGRect(x: 150, y: 150, width: 500, height: 500)])

        XCTAssertEqual(frame.maskRects, [CGRect(x: 190, y: 210, width: 50, height: 50)],
                       "A rect overflowing the composited region must be clipped to it")
    }

    func testDartReportedRect_entirelyOutsideTheBitmap_isDropped() throws {
        let frame = try captureFlutterFrame(flutterViewRect: CGRect(x: 40, y: 60, width: 200, height: 200),
                                            flutterMaskRects: [CGRect(x: 300, y: 300, width: 50, height: 50)])

        XCTAssertEqual(frame.maskRects, [],
                       "A rect outside the composited region describes no masked pixels")
    }
}
