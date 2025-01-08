//
//  ImageScannerTests.swift
//  session_replayTests
//
//  Created by Tomer Har Yoffi on 23/12/2024.
//

import XCTest
import Vision
@testable import Session_Replay

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
            let inputURL = Bundle(for: type(of: strongSelf)).url(forResource: "test_image", withExtension: "png")!
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
        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        
        imageScanner.processImage(at: inputURL, maskAll: true) { success, totalImagesCount, maskedImagesCount in
            XCTAssertTrue(success, "Image processing should succeed.")
            XCTAssertEqual(totalImagesCount, maskedImagesCount)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testProcessImage_withValidInputURL_maskall_false() {
        let expectation = self.expectation(description: "Process image completes")

        // Mock input image
        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        
        imageScanner.processImage(at: inputURL, maskAll: false) { success, totalImagesCount, maskedImagesCount in
            XCTAssertTrue(success, "Image processing should succeed.")
            XCTAssertEqual(2, maskedImagesCount)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5, handler: nil)
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
        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        let ciImage = CIImage(contentsOf: inputURL)!
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
    }

    func testMaskRectangle_withValidObservation_shouldReturnMaskedImage() {
        // Mock input image
        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        let ciImage = CIImage(contentsOf: inputURL)!

        // Mock rectangle observation
        let rectangleObservation = VNRectangleObservation()

        let maskedImage = imageScanner.maskRectangle(in: ciImage, using: rectangleObservation)
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

