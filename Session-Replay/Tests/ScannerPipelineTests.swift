//
//  ScannerPipelineTests.swift
//  session_replayTests
//
//  Created by Tomer Har Yoffi on 24/12/2024.
//

import XCTest
@testable import Session_Replay

class ScannerPipelineTests: XCTestCase {
    var scannerPipeline: ScannerPipeline!
    
    override func setUp() {
        super.setUp()
        scannerPipeline = ScannerPipeline()
    }

    override func tearDown() {
        scannerPipeline = nil
        super.tearDown()
    }

    func testRunPipeline_withAllScannersEnabled() {
        let expectation = self.expectation(description: "Pipeline should complete successfully with all scanners enabled.")

        scannerPipeline.isImageScannerEnabled = true
        scannerPipeline.isTextScannerEnabled = true
        scannerPipeline.isFaceScannerEnabled = true

        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        let options = SessionReplayOptions(maskText: ["confidential"], maskAllImages: true)

        scannerPipeline.runPipeline(inputURL: inputURL, options: options) { result in
            XCTAssertTrue(result, "Pipeline should complete successfully.")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5, handler: nil)
    }

    func testRunPipeline_withOnlyImageScannerEnabled() {
        let expectation = self.expectation(description: "Pipeline should complete successfully with only image scanner enabled.")

        scannerPipeline.isImageScannerEnabled = true
        scannerPipeline.isTextScannerEnabled = false
        scannerPipeline.isFaceScannerEnabled = false

        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        let options = SessionReplayOptions(maskText: nil, maskAllImages: true)

        scannerPipeline.runPipeline(inputURL: inputURL, options: options) { result in
            XCTAssertTrue(result, "Pipeline should complete successfully.")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5, handler: nil)
    }

    func testRunPipeline_withNoScannersEnabled() {
        let expectation = self.expectation(description: "Pipeline should complete successfully with no scanners enabled.")

        scannerPipeline.isImageScannerEnabled = false
        scannerPipeline.isTextScannerEnabled = false
        scannerPipeline.isFaceScannerEnabled = false

        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        let options = SessionReplayOptions(maskText: nil, maskAllImages: false)

        scannerPipeline.runPipeline(inputURL: inputURL, options: options) { result in
            XCTAssertTrue(result, "Pipeline should complete successfully.")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5, handler: nil)
    }

    func testRunPipeline_withSimulatorEnvironment_shouldSkipFaceScanner() {
        #if targetEnvironment(simulator)
        let expectation = self.expectation(description: "Pipeline should complete successfully and skip face scanner on simulator.")

        scannerPipeline.isImageScannerEnabled = false
        scannerPipeline.isTextScannerEnabled = false
        scannerPipeline.isFaceScannerEnabled = true

        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        let options = SessionReplayOptions(maskText: nil, maskAllImages: false)

        scannerPipeline.runPipeline(inputURL: inputURL, options: options) { result in
            XCTAssertTrue(result, "Pipeline should skip face scanner and complete successfully on simulator.")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5, handler: nil)
        #else
        XCTAssertTrue(true, "This test runs only on the simulator.")
        #endif
    }

    func testRunPipeline_withFaceScannerDisabled() {
        let expectation = self.expectation(description: "Pipeline should complete successfully with face scanner disabled.")

        scannerPipeline.isImageScannerEnabled = false
        scannerPipeline.isTextScannerEnabled = false
        scannerPipeline.isFaceScannerEnabled = false

        let inputURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        let options = SessionReplayOptions(maskText: nil, maskAllImages: false)

        scannerPipeline.runPipeline(inputURL: inputURL, options: options) { result in
            XCTAssertTrue(result, "Pipeline should complete successfully with face scanner disabled.")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5, handler: nil)
    }
}
