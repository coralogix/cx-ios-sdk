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
        let expectation = self.expectation(description: "Recognize credit card text")
        
        // Mock input image
        guard let inputURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        guard
            let ciImage = CIImage(contentsOf: inputURL),
            let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)
        else {
            XCTFail("Unable to create CI/CG images from fixture")
            return
        }
        ImageScanner().recognizeText(in: cgImage) { isCreditCard in
            XCTAssertTrue(isCreditCard, "The text recognition should identify the credit card.")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testProcessImage_withValidInputURL_shouldCompleteSuccessfully() {
        let expectation = self.expectation(description: "Process image completes")
        
        // Mock input image
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            let imageData = try Data(contentsOf: originalURL)

            imageScanner.processImage(screenshotData: imageData, maskAll: true) { ciImage in
                XCTAssertNotNil(ciImage)
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
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            // Create a unique file
            //let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            let imageData = try Data(contentsOf: originalURL)

            imageScanner.processImage(screenshotData: imageData, maskAll: false) { ciImage in
                XCTAssertNotNil(ciImage)
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
    
    func testProcessImage_withInvalidScreenshotData_shouldFail() {
        let expectation = self.expectation(description: "Process image fails")
        
        // Invalid Screenshot Data
        let dummyData = "fake-image".data(using: .utf8)!
        
        imageScanner.processImage(screenshotData: dummyData, maskAll: true) { ciImage in
            XCTAssertNil(ciImage)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testIsCreditCardRectangle_withValidRectangle_shouldReturnTrue() {
        let expectation = self.expectation(description: "Detect credit card rectangle")
        
        // Mock input image
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
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
    
    func testMaskRectangle_withValidObservation_shouldReturnMaskedImage() async throws {
        // Mock input image
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }

        // Create a unique file
        let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
        guard let ciImage = CIImage(contentsOf: uniqueFileURL) else {
            XCTFail("Failed to load CIImage from file.")
            return
        }

        // Create a mock rectangle observation (normally you'd configure the bounding box properly)
        let rectangleObservation = VNRectangleObservation(
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        )

        // Act: Call the async masking function
        let maskedImage = await imageScanner.maskRectangle(in: ciImage, using: rectangleObservation)

        // Assert: Check that a masked image was returned
        XCTAssertNotNil(maskedImage, "Masking rectangle should return a valid CIImage.")
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
}

