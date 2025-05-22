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
