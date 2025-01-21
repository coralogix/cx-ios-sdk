////
////  FaceScannerTests.swift
////  session_replayTests
////
////  Created by Coralogix DEV TEAM on 24/12/2024.
////
//
//import XCTest
//import Vision
//import UIKit
//@testable import Session_Replay
//
//class FaceScannerTests: XCTestCase {
//    var faceScanner: FaceScanner!
//
//    override func setUp() {
//        super.setUp()
//        faceScanner = FaceScanner()
//    }
//
//    override func tearDown() {
//        faceScanner = nil
//        super.tearDown()
//    }
//
//    func testProcessImage_withFaces_shouldCompleteSuccessfully() {
//        let expectation = self.expectation(description: "Face detection and masking should complete successfully.")
//
//        // Mock input image URL
//        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image_2", withExtension: "png")!
//        
//        faceScanner.processImage(at: inputURL) { success in
//            XCTAssertTrue(success, "The face detection and masking should succeed.")
//            expectation.fulfill()
//        }
//
//        waitForExpectations(timeout: 5, handler: nil)
//    }
//
//    func testProcessImage_withNoFaces_shouldReturnFalse() {
//        let expectation = self.expectation(description: "Face detection should return false when no faces are present.")
//
//        // Mock input image URL
//        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
//
//        faceScanner.processImage(at: inputURL) { success in
//            XCTAssertFalse(success, "The face detection should fail when no faces are detected.")
//            expectation.fulfill()
//        }
//
//        waitForExpectations(timeout: 5, handler: nil)
//    }
//
//    func testApplyFaceMask_withDetectedFaces_shouldMaskCorrectly() {
//        // Mock input image
//        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image_2", withExtension: "png")!
//        let uiImage = UIImage(contentsOfFile: inputURL.path)!
//
//        // Mock face observations
//        let faceObservation = VNFaceObservation(boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3))
//        let observations = [faceObservation]
//
//        let maskedImage = faceScanner.applyFaceMask(to: uiImage, with: observations)
//        let uiCGImage = uiImage.cgImage?.sha256Digest()
//        let maskedCGImage = maskedImage?.cgImage?.sha256Digest()
//        XCTAssertNotEqual(uiCGImage, maskedCGImage)
//        XCTAssertNotNil(maskedImage, "The masked image should not be nil.")
//    }
//
//    func testApplyFaceMask_withNoDetectedFaces_shouldReturnOriginalImage() {
//        // Mock input image
//        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
//        let uiImage = UIImage(contentsOfFile: inputURL.path)!
//
//        let observations: [VNFaceObservation] = []
//
//        let maskedImage = faceScanner.applyFaceMask(to: uiImage, with: observations)
//
//        XCTAssertNotNil(maskedImage, "The masked image should not be nil.")
////        let uiCGImage = uiImage.cgImage?.sha256Digest()
////        let maskedCGImage = maskedImage?.cgImage?.sha256Digest()
////        XCTAssertEqual(uiCGImage, maskedCGImage)
//    }
//}
