//
//  ScannerPipelineTests.swift
//  SessionReplayTests
//
//  Created by Coralogix DEV TEAM on 11/06/2026.
//

import XCTest
import UIKit
import CoreImage
@testable import SessionReplay

/// Validates the SwiftUI-scoped gating of the OCR text stage and the
/// maskAll image stage (BUGV2-6045): both must run only when the captured
/// scene contained SwiftUI content (`URLEntry.containsSwiftUIContent`).
final class ScannerPipelineTests: XCTestCase {

    private let ciContext = CIContext()

    // MARK: - Helpers

    /// High-contrast monospaced text on white — deterministic input for the
    /// Vision OCR path (mirrors the leak-harness sentinel style).
    private func makeTextImageData() -> Data {
        let size = CGSize(width: 400, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 36, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            ("SENTINEL TEXT 12345" as NSString).draw(at: CGPoint(x: 16, y: 40),
                                                     withAttributes: attributes)
        }
        return image.pngData()!
    }

    private func makeEntry(data: Data, containsSwiftUIContent: Bool) -> URLEntry {
        URLEntry(url: URL(fileURLWithPath: "/tmp/scanner_pipeline_test.png"),
                 timestamp: 0,
                 screenshotId: "test-screenshot-id",
                 segmentIndex: 0,
                 page: "0",
                 screenshotData: data,
                 point: nil,
                 containsSwiftUIContent: containsSwiftUIContent,
                 completion: nil)
    }

    private func pngBytes(_ image: CIImage) -> Data? {
        ciContext.pngRepresentation(of: image,
                                    format: .RGBA8,
                                    colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    private func runPipeline(options: SessionReplayOptions, entry: URLEntry) -> CIImage? {
        let expectation = self.expectation(description: "pipeline completes")
        var result: CIImage?
        ScannerPipeline().runPipeline(options: options, urlEntry: entry) { ciImage, _ in
            result = ciImage
            expectation.fulfill()
        }
        waitForExpectations(timeout: 30, handler: nil)
        return result
    }

    // MARK: - Tests

    func testNonSwiftUICapture_skipsTextAndImageStages_evenWithMaskTextSet() {
        let data = makeTextImageData()
        let options = SessionReplayOptions(maskText: [".*"],
                                           maskOnlyCreditCards: false,
                                           maskAllImages: true)
        let entry = makeEntry(data: data, containsSwiftUIContent: false)

        guard let output = runPipeline(options: options, entry: entry) else {
            XCTFail("Pipeline returned nil image")
            return
        }

        // No stage may touch the frame: output must be pixel-identical to input.
        let inputImage = CIImage(data: data)!
        XCTAssertEqual(pngBytes(output), pngBytes(inputImage),
                       "Non-SwiftUI capture must pass through the pipeline unmodified")
    }

    func testSwiftUICapture_masksTextWithMatchAllPattern() {
        let data = makeTextImageData()
        let options = SessionReplayOptions(maskText: [".*"],
                                           maskOnlyCreditCards: false,
                                           maskAllImages: false)
        let entry = makeEntry(data: data, containsSwiftUIContent: true)

        guard let output = runPipeline(options: options, entry: entry) else {
            XCTFail("Pipeline returned nil image")
            return
        }

        let inputImage = CIImage(data: data)!
        XCTAssertEqual(output.extent, inputImage.extent)
        XCTAssertNotEqual(pngBytes(output), pngBytes(inputImage),
                          "SwiftUI capture with maskText must run the OCR stage and alter the frame")
    }

    func testSwiftUICapture_withoutMaskText_skipsTextStage() {
        let data = makeTextImageData()
        let options = SessionReplayOptions(maskText: nil,
                                           maskOnlyCreditCards: false,
                                           maskAllImages: false)
        let entry = makeEntry(data: data, containsSwiftUIContent: true)

        guard let output = runPipeline(options: options, entry: entry) else {
            XCTFail("Pipeline returned nil image")
            return
        }

        let inputImage = CIImage(data: data)!
        XCTAssertEqual(pngBytes(output), pngBytes(inputImage),
                       "Text stage requires a non-empty maskText even for SwiftUI captures")
    }
}
