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
        
        let operationId = UUID()
        self.currentOperationId = operationId
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        do {
            let options = SessionReplayOptions(maskText: ["confidential"],
                                               maskImages: true,
                                               maskFaces: true)
           
            let imageData = try Data(contentsOf: originalURL)
            let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                    timestamp: Date().timeIntervalSince1970,
                                    screenshotId: UUID().uuidString,
                                    segmentIndex: 0,
                                    page: "0",
                                    screenshotData: imageData,
                                    point: CGPoint(x: 100.0, y: 100.0),
                                    completion: nil)
            
            scannerPipeline.runPipeline(options: options, urlEntry: urlEntry) { ciImage, urlEntry in
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
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            let options = SessionReplayOptions(maskText: nil,
                                               maskImages: true,
                                               maskAllImages: true,
                                               maskFaces: false)
           
            let operationId = UUID()
            self.currentOperationId = operationId
            let imageData = try Data(contentsOf: originalURL)
            
            let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                    timestamp: Date().timeIntervalSince1970,
                                    screenshotId: UUID().uuidString,
                                    segmentIndex: 0,
                                    page: "0",
                                    screenshotData: imageData,
                                    point: CGPoint(x: 100.0, y: 100.0),
                                    completion: nil)
            scannerPipeline.runPipeline(options: options, urlEntry: urlEntry) { ciImage, urlEntry in
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
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            let options = SessionReplayOptions(maskText: nil,
                                               maskImages: false,
                                               maskAllImages: false,
                                               maskFaces: false)
                       let operationId = UUID()
            self.currentOperationId = operationId
            let imageData = try Data(contentsOf: originalURL)
            
            let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                    timestamp: Date().timeIntervalSince1970,
                                    screenshotId: UUID().uuidString,
                                    segmentIndex: 0,
                                    page: "0",
                                    screenshotData: imageData,
                                    point: CGPoint(x: 100.0, y: 100.0),
                                    completion: nil)
            
            scannerPipeline.runPipeline(options: options, urlEntry: urlEntry) { ciImage, urlEntry in
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
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        do {
            let options = SessionReplayOptions(maskText: nil,
                                               maskImages: false,
                                               maskAllImages: false,
                                               maskFaces: false)
            let operationId = UUID()
            self.currentOperationId = operationId
            let imageData = try Data(contentsOf: originalURL)
            let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                    timestamp: Date().timeIntervalSince1970,
                                    screenshotId: UUID().uuidString,
                                    segmentIndex: 0,
                                    page: "0",
                                    screenshotData: imageData,
                                    point: CGPoint(x: 100.0, y: 100.0),
                                    completion: nil)
            scannerPipeline.runPipeline(options: options, urlEntry: urlEntry) { ciImage, urlEntry in
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
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        do {
            let options = SessionReplayOptions(maskText: nil,
                                               maskImages: true,
                                               maskAllImages: true,
                                               maskFaces: false)
            let operationId = UUID()
            self.currentOperationId = operationId
            let imageData = try Data(contentsOf: originalURL)
            let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                                timestamp: Date().timeIntervalSince1970,
                                                screenshotId: UUID().uuidString,
                                                segmentIndex: 0,
                                                page: "0",
                                                screenshotData: imageData,
                                                point: CGPoint(x: 100.0, y: 100.0),
                                                completion: nil)
            
                       
            scannerPipeline.runPipeline(options: options, urlEntry: urlEntry) { ciImage, urlEntry in
                XCTAssertNotNil(ciImage, "Pipeline should complete successfully with face scanner disabled.")
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
}
