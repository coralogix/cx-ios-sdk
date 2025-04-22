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
    
    func testPrintBundleContents() {
#if SWIFT_PACKAGE
    let bundle = Bundle.module
#else
    let bundle = Bundle(for: Self.self) // or SDKResources.bundle if using wrapper
#endif

    guard let path = bundle.resourcePath else {
        XCTFail("bundle.resourcePath is nil")
        return
    }

    do {
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        print("📦 Bundle contents: \(contents)")
    } catch {
        XCTFail("Failed to read bundle contents: \(error)")
    }
    }

    func testProcessImage_withValidInput_shouldCompleteSuccessfully() {
        let expectation = self.expectation(description: "Image processing should complete successfully.")
        
        guard let originalURL = SDKResources.bundle.url(forResource: "test_image", withExtension: "png") else {
            XCTFail("test_image.png not found in Bundle.module")
            return
        }
        
        do {
            // Create a unique file
            let uniqueFileURL = try createUniqueFile(from: originalURL, withExtension: "png")
            print(uniqueFileURL)
            
            clickScanner.processImage(at: uniqueFileURL, x: 100, y: 100) { success in
                XCTAssertTrue(success, "The image processing should succeed.")
                XCTAssertTrue(FileManager.default.fileExists(atPath: uniqueFileURL.path), "The output file should exist.")
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5, handler: nil)
        } catch {
            XCTFail("Failed to create unique file: \(error)")
        }
    }
}
