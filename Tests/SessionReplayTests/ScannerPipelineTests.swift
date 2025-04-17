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
        
        let originalURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        do {
            let options = SessionReplayOptions(maskText: ["confidential"], maskAllImages: true)
            
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            scannerPipeline.runPipeline(inputURL: uniqueFileURL, options: options) { result in
                XCTAssertTrue(result, "Pipeline should complete successfully.")
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
        
        let originalURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let options = SessionReplayOptions(maskText: nil, maskAllImages: true)
            
            scannerPipeline.runPipeline(inputURL: uniqueFileURL, options: options) { result in
                XCTAssertTrue(result, "Pipeline should complete successfully.")
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
        
        let originalURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let options = SessionReplayOptions(maskText: nil, maskAllImages: false)
            
            scannerPipeline.runPipeline(inputURL: uniqueFileURL, options: options) { result in
                XCTAssertTrue(result, "Pipeline should complete successfully.")
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
        
        let originalURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let options = SessionReplayOptions(maskText: nil, maskAllImages: false)
            
            scannerPipeline.runPipeline(inputURL: uniqueFileURL, options: options) { result in
                XCTAssertTrue(result, "Pipeline should skip face scanner and complete successfully on simulator.")
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
        
        let originalURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            
            let options = SessionReplayOptions(maskText: nil, maskAllImages: false)
            
            scannerPipeline.runPipeline(inputURL: uniqueFileURL, options: options) { result in
                XCTAssertTrue(result, "Pipeline should complete successfully with face scanner disabled.")
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
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
