//
//  ClickScannerTests.swift
//  Session-Replay-Tests
//
//  Created by Tomer Har Yoffi on 28/01/2025.
//

import XCTest
@testable import SessionReplay

class ClickScannerTests: XCTestCase {
    var clickScanner: ClickScanner!
    
    override func setUp() {
        super.setUp()
        clickScanner = ClickScanner()
    }
    
    override func tearDown() {
        clickScanner = nil
        super.tearDown()
    }
    
    func testProcessImage_withValidInput_shouldCompleteSuccessfully() {
        let expectation = self.expectation(description: "Image processing should complete successfully.")
        
        let originalURL = Bundle(for: type(of: self)).url(forResource: "test_image", withExtension: "png")!
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            print(uniqueFileURL)
            
            clickScanner.processImage(at: uniqueFileURL) { success in
                XCTAssertTrue(success, "The image processing should succeed.")
                XCTAssertTrue(FileManager.default.fileExists(atPath: uniqueFileURL.path), "The output file should exist.")
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
