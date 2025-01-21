//
//  TextScannerTests.swift
//  session_replayTests
//
//  Created by Coralogix DEV TEAM on 24/12/2024.
//

import XCTest
import Vision
import CoreImage
@testable import Session_Replay

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
        
        let originalURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            textScanner.processImage(at: uniqueFileURL, maskText: ["Sign"]) { success, totalTextCount, maskedTextCount in
                XCTAssertTrue(success, "The image processing should succeed.")
                XCTAssertTrue(FileManager.default.fileExists(atPath: uniqueFileURL.path), "The output file should exist.")
                XCTAssertEqual(1, maskedTextCount)
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }

    func testProcessImage_withInvalidInput_shouldFail() {
        let expectation = self.expectation(description: "Image processing should fail.")

        // Invalid input URL
        let invalidURL = URL(fileURLWithPath: "/invalid/path/to/image.png")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("output_image.png")

        textScanner.processImage(at: invalidURL, maskText: ["confidential"]) { success, totalTextCount, maskedTextCount in
            XCTAssertFalse(success, "The image processing should fail for an invalid input URL.")
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path), "The output file should not exist.")
            XCTAssertEqual(0, maskedTextCount)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5, handler: nil)
    }

    func testMaskText_withNoPatterns_shouldMaskAllText() {
        // Mock input image
        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        let ciImage = CIImage(contentsOf: inputURL)!

        let (maskedImage, totalTextCount, maskedTextCount) = textScanner.maskText(in: ciImage, with: nil)

        XCTAssertNotNil(maskedImage, "The masked image should not be nil.")
        // Additional verification of the masked content can be done by saving and visually inspecting the result.
        XCTAssertEqual(totalTextCount, maskedTextCount)
    }

    func testMaskText_withNoText_shouldReturnOriginalImage() {
        // Mock input image without text
        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image_2", withExtension: "png")!
        let ciImage = CIImage(contentsOf: inputURL)!

        let (maskedImage, totalTextCount, maskedTextCount) = textScanner.maskText(in: ciImage, with: ["anyPattern"])

        XCTAssertNotNil(maskedImage, "The masked image should not be nil.")
        XCTAssertEqual(ciImage.extent, maskedImage.extent, "The output image should have the same extent as the input image.")
        XCTAssertEqual(0, totalTextCount)
        XCTAssertEqual(0, maskedTextCount)
    }
    
    func testMaskText_withSpecificPattern_shouldMaskOnlyMatchingText() {
        
        // Mock input image
        let originalURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let ciImage = CIImage(contentsOf: uniqueFileURL)!
            
            let patterns = ["Stop"]
            let (maskedImage, totalTextCount, maskedTextCount) = textScanner.maskText(in: ciImage, with: patterns)
            
            XCTAssertNotNil(maskedImage, "The masked image should not be nil.")
            // Additional verification of the masked content can be done by saving and visually inspecting the result.
            XCTAssertEqual(31, totalTextCount)
            XCTAssertEqual(1, maskedTextCount)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
    
    /// Creates a unique copy of a file with a random name in a temporary directory.
    ///
    /// - Parameters:
    ///   - originalURL: The URL of the original file.
    ///   - extension: The file extension for the new file (optional; inferred if nil).
    /// - Returns: The URL of the newly created unique file.
    /// - Throws: An error if the file copy operation fails.
    func createUniqueFile(from originalURL: URL, withExtension fileExtension: String? = nil) throws -> URL {
        // Create a unique directory for the test
        let uniqueTestDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: uniqueTestDir, withIntermediateDirectories: true)
        
        // Generate a random file name
        let randomFileName = UUID().uuidString
        let fullFileName = fileExtension != nil ? "\(randomFileName).\(fileExtension!)" : randomFileName
        
        // Generate the URL for the unique file
        let uniqueFileURL = uniqueTestDir.appendingPathComponent(fullFileName)
        
        // Copy the original file to the unique location
        try FileManager.default.copyItem(at: originalURL, to: uniqueFileURL)
        
        return uniqueFileURL
    }
}
