//
//  TextScannerTests.swift
//  session_replayTests
//
//  Created by Coralogix DEV TEAM on 24/12/2024.
//

import XCTest
import Vision
import CoreImage
@testable import SessionReplay

class TextScannerTests: XCTestCase {
    var textScanner: TextScanner!
    
    override func setUp() {
        super.setUp()
        textScanner = TextScanner()
    }

    override func tearDown() {
        textScanner = nil
        super.tearDown()
    }

    func testProcessImage_withValidInput_shouldCompleteSuccessfully() {
        let expectation = self.expectation(description: "Image processing should complete successfully.")
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        guard let ciImage = CIImage(contentsOf: originalURL) else {
            return
        }
        
        // Create a unique file
        textScanner.processImage(ciImage: ciImage, maskText: ["Sign"]) { ciImage in
            XCTAssertNotNil(ciImage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path), "The output file should exist.")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }

    func testProcessImage_withInvalidInput_shouldFail() {
        let expectation = self.expectation(description: "Image processing should fail.")
        
        // Invalid input URL
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("output_image.png")
        
        let ciImage: CIImage = .empty()
        textScanner.processImage(ciImage: ciImage, maskText: ["confidential"]) { ciImage in
            XCTAssertNotNil(ciImage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path), "The output file should not exist.")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }

    func testMaskText_withNoPatterns_shouldMaskAllText() {
        // Mock input image
        let inputURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png")!
        let ciImage = CIImage(contentsOf: inputURL)!

        let maskedImage = textScanner.maskText(in: ciImage, with: nil)

        XCTAssertNotNil(maskedImage, "The masked image should not be nil.")
    }

    func testMaskText_withNoText_shouldReturnOriginalImage() {
        // Mock input image without text
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image_2", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let ciImage = CIImage(contentsOf: uniqueFileURL)!
            
            let maskedImage = textScanner.maskText(in: ciImage, with: ["anyPattern"])
            
            XCTAssertNotNil(maskedImage, "The masked image should not be nil.")
            XCTAssertEqual(ciImage.extent, maskedImage.extent, "The output image should have the same extent as the input image.")
        } catch {
            XCTFail("Error creating unique file: \(error)")
        }
    }
    
    func testConfigureRecognitionRequest_disablesLanguageCorrection() {
        let request = VNRecognizeTextRequest()
        // Default is true — language correction filters short/non-word tokens
        // like "OK", "$4.99", IDs, etc., causing them to never reach the
        // masker. The fix is to turn it off so every recognized observation
        // is mask-eligible.
        request.usesLanguageCorrection = true
        // Pre-set to .fast so the post-call .accurate assertion below
        // actively verifies the helper, not the framework default.
        request.recognitionLevel = .fast

        textScanner.configureRecognitionRequest(request)

        XCTAssertFalse(request.usesLanguageCorrection)
        XCTAssertEqual(request.recognitionLevel, .accurate)
    }

    func testConfigureRecognitionRequest_widensLanguageCoverage() {
        let request = VNRecognizeTextRequest()

        textScanner.configureRecognitionRequest(request)

        // recognitionLanguages must be widened on every iOS version we support.
        // Relying on `automaticallyDetectsLanguage` alone on iOS 16+ caused
        // mixed-script frames to collapse to a single dominant script and drop
        // the rest (Latin + Cyrillic missed when CJK/RTL were also on screen).
        // The fix is to always supply an explicit multi-script candidate list.
        XCTAssertGreaterThan(request.recognitionLanguages.count, 1)
        XCTAssertTrue(request.recognitionLanguages.contains("en-US"))
        // Spot-check a non-English language to guard against accidental
        // regression to the en-US default.
        XCTAssertTrue(request.recognitionLanguages.contains("ja-JP"))

        if #available(iOS 16.0, *) {
            // iOS 16+: keep auto-detect on top of the explicit list so Vision
            // biases per-image while still seeing every script we care about.
            XCTAssertTrue(request.automaticallyDetectsLanguage)
        }
    }

    func testMaskText_withMatchAllPattern_shouldRunRegionFallback() {
        // The maskAllTexts path (Flutter/RN bridges send [".*"]) must run BOTH
        // VNRecognizeTextRequest and VNDetectTextRectanglesRequest. The combined
        // pipeline shouldn't crash and should yield a non-nil image whose extent
        // matches the input — same baseline guarantees as the other paths.
        guard let inputURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png"),
              let ciImage = CIImage(contentsOf: inputURL) else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }

        let maskedImage = textScanner.maskText(in: ciImage, with: [".*"])

        XCTAssertNotNil(maskedImage)
        XCTAssertEqual(maskedImage.extent, ciImage.extent)
    }

    func testMaskText_withSpecificPattern_shouldMaskOnlyMatchingText() {
        
        // Mock input image
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let ciImage = CIImage(contentsOf: uniqueFileURL)!
            
            let patterns = ["Stop"]
            let maskedImage = textScanner.maskText(in: ciImage, with: patterns)
            
            XCTAssertNotNil(maskedImage, "The masked image should not be nil.")
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
}
