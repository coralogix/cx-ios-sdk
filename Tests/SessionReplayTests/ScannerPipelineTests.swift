//
//  ScannerPipelineTests.swift
//  session_replayTests
//
//  Created by Coralogix DEV TEAM on 24/12/2024.
//

import XCTest
@testable import SessionReplay

class ScannerPipelineTests: XCTestCase {
    var scannerPipeline: ScannerPipeline!
    var currentOperationId: UUID? // Track current operation

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
        let operationId = UUID()
        self.currentOperationId = operationId
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        do {
            let options = SessionReplayOptions(maskText: ["confidential"], maskAllImages: true)
            
            let imageData = try Data(contentsOf: originalURL)

            scannerPipeline.runPipelineWithCancellation(
                screenshotData: imageData,
                options: options,
                operationId: operationId,
                isValid: { [weak self] id in
                    return self?.currentOperationId == id
                }) { ciImage in
                XCTAssertNotNil(ciImage, "Pipeline should complete successfully.")
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
    
    func testRunPipeline_withOnlyImageScannerEnabled() {
        let expectation = self.expectation(description: "Pipeline should complete successfully with only image scanner enabled.")
        
        scannerPipeline.isImageScannerEnabled = true
        scannerPipeline.isTextScannerEnabled = false
        scannerPipeline.isFaceScannerEnabled = false
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            let options = SessionReplayOptions(maskText: nil, maskAllImages: true)
            let operationId = UUID()
            self.currentOperationId = operationId
            let imageData = try Data(contentsOf: originalURL)
            
            scannerPipeline.runPipelineWithCancellation(
                screenshotData: imageData,
                options: options,
                operationId: operationId,
            isValid: { [weak self] id in
                return self?.currentOperationId == id
            }) { ciImage in
                XCTAssertNotNil(ciImage, "Pipeline should complete successfully.")
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
    
    func testRunPipeline_withNoScannersEnabled() {
        let expectation = self.expectation(description: "Pipeline should complete successfully with no scanners enabled.")
        
        scannerPipeline.isImageScannerEnabled = false
        scannerPipeline.isTextScannerEnabled = false
        scannerPipeline.isFaceScannerEnabled = false
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            let options = SessionReplayOptions(maskText: nil, maskAllImages: false)
            let operationId = UUID()
            self.currentOperationId = operationId
            let imageData = try Data(contentsOf: originalURL)

            scannerPipeline.runPipelineWithCancellation(
                screenshotData: imageData,
                options: options,
                operationId: operationId,
                isValid: { [weak self] id in
                    return self?.currentOperationId == id
                }) { ciImage in
                XCTAssertNotNil(ciImage, "Pipeline should complete successfully.")
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
    
    func testRunPipeline_withSimulatorEnvironment_shouldSkipFaceScanner() {
#if targetEnvironment(simulator)
        let expectation = self.expectation(description: "Pipeline should complete successfully and skip face scanner on simulator.")
        
        scannerPipeline.isImageScannerEnabled = false
        scannerPipeline.isTextScannerEnabled = false
        scannerPipeline.isFaceScannerEnabled = true
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let options = SessionReplayOptions(maskText: nil, maskAllImages: false)
            let operationId = UUID()
            self.currentOperationId = operationId
            let imageData = try Data(contentsOf: originalURL)

            scannerPipeline.runPipelineWithCancellation(
                screenshotData: imageData,
                options: options,
                operationId: operationId,
                isValid: { [weak self] id in
                    return self?.currentOperationId == id
                }
            ) { ciImage in
                XCTAssertNotNil(ciImage, "Pipeline should skip face scanner and complete successfully on simulator.")
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }

#else
            XCTAssertTrue(true, "This test runs only on the simulator.")
#endif
    }
    
    func testRunPipeline_withFaceScannerDisabled() {
        let expectation = self.expectation(description: "Pipeline should complete successfully with face scanner disabled.")
        
        scannerPipeline.isImageScannerEnabled = false
        scannerPipeline.isTextScannerEnabled = false
        scannerPipeline.isFaceScannerEnabled = false
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let options = SessionReplayOptions(maskText: nil, maskAllImages: false)
            let operationId = UUID()
            self.currentOperationId = operationId
            let imageData = try Data(contentsOf: originalURL)

            scannerPipeline.runPipelineWithCancellation(
                screenshotData: imageData,
                options: options,
                operationId: operationId,
                isValid: { [weak self] id in
                    return self?.currentOperationId == id
                }) { ciImage in
                    XCTAssertNotNil(ciImage, "Pipeline should complete successfully with face scanner disabled.")
                    expectation.fulfill()
                }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
}
