//
//  ImageScannerTests.swift
//  session_replayTests
//
//  Created by Coralogix DEV TEAM on 23/12/2024.
//

import XCTest
import Vision
@testable import SessionReplay

class ImageScannerTests: XCTestCase {
    var imageScanner: ImageScanner!
    
    override func setUp() {
        super.setUp()
        imageScanner = ImageScanner()
    }
    
    override func tearDown() {
        imageScanner = nil
        super.tearDown()
    }
    
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        return false
    }
    
    func testRecognizeText_withValidCreditCardText_shouldReturnTrue() {
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else {
                return
            }
            
            let expectation = strongSelf.expectation(description: "Recognize credit card text")
            
            // Mock input image
            guard let inputURL = Bundle.module.url(forResource: "test_image", withExtension: "png") else {
                XCTFail("test_image.png not found in Bundle.module")
                return
            }
            let ciImage = CIImage(contentsOf: inputURL)!
            let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)!
            
            ImageScanner().recognizeText(in: cgImage) { isCreditCard in
                XCTAssertTrue(isCreditCard, "The text recognition should identify the credit card.")
                expectation.fulfill()
            }
            
            strongSelf.waitForExpectations(timeout: 5, handler: nil)
        }
    }
    
    func testProcessImage_withValidInputURL_shouldCompleteSuccessfully() {
        let expectation = self.expectation(description: "Process image completes")
        
        // Mock input image
        guard let originalURL = Bundle.module.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            imageScanner.processImage(at: uniqueFileURL, maskAll: true) { success, totalImagesCount, maskedImagesCount in
                XCTAssertTrue(success, "Image processing should succeed.")
                XCTAssertEqual(totalImagesCount, maskedImagesCount)
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
    
    func testProcessImage_withValidInputURL_maskall_false() {
        let expectation = self.expectation(description: "Process image completes")
        
        // Mock input image
        guard let originalURL = Bundle.module.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            imageScanner.processImage(at: uniqueFileURL, maskAll: false) { success, totalImagesCount, maskedImagesCount in
                XCTAssertTrue(success, "Image processing should succeed.")
                XCTAssertEqual(2, maskedImagesCount)
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
    
    func testProcessImage_withInvalidInputURL_shouldFail() {
        let expectation = self.expectation(description: "Process image fails")
        
        // Invalid input URL
        let invalidURL = URL(fileURLWithPath: "invalid/path/to/image.jpg")
        
        imageScanner.processImage(at: invalidURL, maskAll: true) { success, totalImagesCount, maskedImagesCount in
            XCTAssertFalse(success, "Image processing should fail with invalid URL.")
            XCTAssertEqual(0, maskedImagesCount)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testIsCreditCardRectangle_withValidRectangle_shouldReturnTrue() {
        let expectation = self.expectation(description: "Detect credit card rectangle")
        
        // Mock input image
        guard let originalURL = Bundle.module.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let ciImage = CIImage(contentsOf: uniqueFileURL)!
            let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)!
            
            // Generate actual rectangle observation
            guard let rectangleObservation = createRectangleObservation(from: cgImage) else {
                XCTFail("Failed to create rectangle observation")
                return
            }
            
            imageScanner.isCreditCardRectangle(cgImage: cgImage, observation: rectangleObservation) { isCreditCard in
                XCTAssertTrue(isCreditCard, "The rectangle should be identified as a credit card.")
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
    
    func testMaskRectangle_withValidObservation_shouldReturnMaskedImage() {
        // Mock input image
        guard let originalURL = Bundle.module.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let ciImage = CIImage(contentsOf: uniqueFileURL)!
            
            // Mock rectangle observation
            let rectangleObservation = VNRectangleObservation()
            
            let maskedImage = imageScanner.maskRectangle(in: ciImage, using: rectangleObservation)
            XCTAssertNotNil(maskedImage, "Masking rectangle should return a valid CIImage.")
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
    
    // MARK: - Private
    private func createRectangleObservation(from image: CGImage) -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        do {
            try handler.perform([request])
            return request.results?.first as? VNRectangleObservation
        } catch {
            XCTFail("Failed to detect rectangles: \(error)")
            return nil
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

