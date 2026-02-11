//
//  NetworkInstrumentationUITests.swift
//  DemoAppUITests
//
//  Created by Coralogix DEV TEAM on 05/02/2026.
//
//  These UI tests trigger network requests in the DemoApp and verify
//  that instrumentation works by checking console logs.
//
//  VERIFICATION: Check Xcode console for expected log messages during test execution.
//

import XCTest

final class NetworkInstrumentationUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Enable test mode
        app.launchArguments = ["--uitesting"]
        
        app.launch()
        
        // Clear previous logs
        clearTestLogs()
    }
    
    // MARK: - Helper Methods
    
    private func clearTestLogs() {
        // Clear the shared test log file
        let testLogsPath = "/tmp/coralogix_test_logs.txt"
        try? FileManager.default.removeItem(atPath: testLogsPath)
    }
    
    private func getTestLogs() -> String {
        // Read from fixed shared location
        let testLogsPath = "/tmp/coralogix_test_logs.txt"
        
        if let content = try? String(contentsOfFile: testLogsPath, encoding: .utf8) {
            return content
        }
        
        print("⚠️ Log file not found at: \(testLogsPath)")
        print("⚠️ File exists: \(FileManager.default.fileExists(atPath: testLogsPath))")
        
        return ""
    }
    
    private func verifyLogContains(_ expectedMessages: [String], file: StaticString = #file, line: UInt = #line) {
        // Wait for logs to be written
        Thread.sleep(forTimeInterval: 3)
        
        let testLogsPath = "/tmp/coralogix_test_logs.txt"
        let fileExists = FileManager.default.fileExists(atPath: testLogsPath)
        print("\n📂 Log file exists at \(testLogsPath): \(fileExists)")
        
        let logs = getTestLogs()
        
        if logs.isEmpty {
            print("❌ No test logs found")
            print("   File exists: \(fileExists)")
            print("   Path: \(testLogsPath)")
            print("   Launch args: \(app.launchArguments)")
            XCTFail("❌ No test logs found. Check test logging is enabled.", file: file, line: line)
            return
        }
        
        print("\n📝 Captured Test Logs (\(logs.count) chars):")
        print(logs)
        print("\n")
        
        var allFound = true
        for expectedMessage in expectedMessages {
            if logs.contains(expectedMessage) {
                print("✅ Found: \(expectedMessage)")
            } else {
                print("❌ Missing: \(expectedMessage)")
                allFound = false
            }
        }
        
        if !allFound {
            XCTFail("❌ Some expected log messages were not found", file: file, line: line)
        }
    }
    
    // MARK: - Test Cases
    
    /// Test async/await POST request instrumentation
    /// Automatically validates SDK captured and instrumented the request
    func testAsyncAwaitRequest() throws {
        print("\n========================================")
        print("🧪 TEST: Async/Await Network Request")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10), "Network instrumentation button should exist")
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap Async/Await button
        let asyncAwaitButton = app.staticTexts["Async/Await example"].firstMatch
        XCTAssertTrue(asyncAwaitButton.waitForExistence(timeout: 10), "Async/await button should exist")
        asyncAwaitButton.tap()
        
        // Wait for network request to complete
        Thread.sleep(forTimeInterval: 3)
        
        // Verify expected log messages were written
        verifyLogContains([
            "✅ Detected async/await context",
            "[FakeDelegate] didFinishCollecting called",
            "Logging response for taskId:",
            "status: 201"
        ])
    }
    
    /// Test traditional network request (completion handler based)
    /// Validates SDK instruments traditional requests (should NOT see async/await logs)
    func testTraditionalNetworkRequest() throws {
        print("\n========================================")
        print("🧪 TEST: Traditional Network Request")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10))
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap Successful network request button
        let successButton = app.staticTexts["Successful network request"].firstMatch
        XCTAssertTrue(successButton.waitForExistence(timeout: 10))
        successButton.tap()
        
        // Wait for network request to complete
        Thread.sleep(forTimeInterval: 3)
        
        // Verify expected log messages
        verifyLogContains([
            "Logging response for taskId:",
            "status: 200"
        ])
        
        // Verify it did NOT detect async/await
        let logs = getTestLogs()
        XCTAssertFalse(logs.contains("✅ Detected async/await context"), 
                      "Traditional request should NOT be detected as async/await")
    }
    
    /// Test failing network request instrumentation
    /// Validates SDK captures error/failed requests (404 status)
    func testFailingNetworkRequest() throws {
        print("\n========================================")
        print("🧪 TEST: Failing Network Request")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10))
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap Failing network request button
        let failButton = app.staticTexts["Failing network request"].firstMatch
        XCTAssertTrue(failButton.waitForExistence(timeout: 10))
        failButton.tap()
        
        // Wait for network request to complete/fail
        Thread.sleep(forTimeInterval: 3)
        
        // Verify expected log messages (404 error response)
        verifyLogContains([
            "Logging response for taskId:",
            "status: 404"
        ])
    }
    
    /// Test traditional POST request instrumentation
    /// Validates SDK instruments POST requests with completion handlers
    func testPostRequest() throws {
        print("\n========================================")
        print("🧪 TEST: POST Request")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10))
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap POST request button
        let postButton = app.staticTexts["POST request"].firstMatch
        XCTAssertTrue(postButton.waitForExistence(timeout: 10))
        postButton.tap()
        
        // Wait for network request to complete
        Thread.sleep(forTimeInterval: 3)
        
        // Verify expected log messages
        verifyLogContains([
            "Logging response for taskId:",
            "status: 201"
        ])
    }
    
    /// Test traditional GET request instrumentation
    /// Validates SDK instruments GET requests with completion handlers
    func testGetRequest() throws {
        print("\n========================================")
        print("🧪 TEST: GET Request")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10))
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap GET request button
        let getButton = app.staticTexts["GET request"].firstMatch
        XCTAssertTrue(getButton.waitForExistence(timeout: 10))
        getButton.tap()
        
        // Wait for network request to complete
        Thread.sleep(forTimeInterval: 3)
        
        // Verify expected log messages
        verifyLogContains([
            "Logging response for taskId:",
            "status: 200"
        ])
    }
    
    // NOTE: Flutter tests removed - Flutter network requests use setNetworkRequestContext() API
    // which is a manual reporting mechanism (not URLSession instrumentation).
    // These should be tested separately with integration tests, not URLSession instrumentation tests.
    
    /// Test Alamofire request instrumentation (third-party library)
    /// Validates hybrid approach - setState: fallback captures Alamofire requests
    func testAlamofireRequest() throws {
        print("\n========================================")
        print("🧪 TEST: Alamofire Request")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10))
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap Alamofire success button
        let alamofireButton = app.staticTexts["Alamofire success"].firstMatch
        XCTAssertTrue(alamofireButton.waitForExistence(timeout: 10))
        alamofireButton.tap()
        
        // Wait for network request to complete
        Thread.sleep(forTimeInterval: 3)
        
        // Verify Alamofire request was captured via setState: fallback
        verifyLogContains([
            "Fallback logging response for taskId:",
            "status: 200"
        ])
    }
    
    /// Test Alamofire failure request instrumentation
    /// Validates setState: fallback captures Alamofire error requests
    func testAlamofireFailureRequest() throws {
        print("\n========================================")
        print("🧪 TEST: Alamofire Failure Request")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10))
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap Alamofire failure button
        let alamofireFailButton = app.staticTexts["Alamofire failure"].firstMatch
        XCTAssertTrue(alamofireFailButton.waitForExistence(timeout: 10))
        alamofireFailButton.tap()
        
        // Wait for network request to complete/fail
        Thread.sleep(forTimeInterval: 3)
        
        // Verify Alamofire error was captured via setState: fallback
        // Note: Alamofire validates responses and may not set error for 404s
        // Check for either error logging or response logging with 404 status
        let logs = getTestLogs()
        let hasErrorLog = logs.contains("Fallback logging error for taskId:")
        let hasResponseWith404 = logs.contains("Fallback logging response for taskId:") && logs.contains("status: 404")
        
        XCTAssertTrue(hasErrorLog || hasResponseWith404, 
                     "Should capture Alamofire 404 via fallback (either as error or response)")
    }
    
    /// Test Alamofire upload instrumentation
    /// Validates setState: fallback captures Alamofire upload requests (2MB file)
    func testAlamofireUploadRequest() throws {
        print("\n========================================")
        print("🧪 TEST: Alamofire Upload Request")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10))
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap Alamofire upload button
        let uploadButton = app.staticTexts["Alamofire upload"].firstMatch
        XCTAssertTrue(uploadButton.waitForExistence(timeout: 10))
        uploadButton.tap()
        
        // Wait longer for upload to complete (2MB file)
        Thread.sleep(forTimeInterval: 8)
        
        // Verify Alamofire upload was captured via setState: fallback
        verifyLogContains([
            "Fallback logging response for taskId:"
        ])
    }
    
    /// Test AFNetworking request instrumentation (legacy library)
    /// Validates setState: fallback captures AFNetworking requests
    func testAFNetworkingRequest() throws {
        print("\n========================================")
        print("🧪 TEST: AFNetworking Request")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10))
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap AFNetworking request button
        let afButton = app.staticTexts["AFNetworking request"].firstMatch
        XCTAssertTrue(afButton.waitForExistence(timeout: 10))
        afButton.tap()
        
        // Wait for network request to complete
        Thread.sleep(forTimeInterval: 3)
        
        // Verify AFNetworking request was captured via setState: fallback
        verifyLogContains([
            "Fallback logging response for taskId:",
            "status: 200"
        ])
    }
    
    /// Test SDWebImage download instrumentation
    /// Validates setState: fallback captures image downloads from third-party library
    func testSDWebImageDownload() throws {
        print("\n========================================")
        print("🧪 TEST: SDWebImage Download")
        print("========================================\n")
        
        // Navigate to Network Instrumentation
        let networkButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkButton.waitForExistence(timeout: 10))
        networkButton.tap()
        Thread.sleep(forTimeInterval: 1)
        
        // Tap SDWebImage download button
        let imageButton = app.staticTexts["Download image (SDWebImage)"].firstMatch
        XCTAssertTrue(imageButton.waitForExistence(timeout: 10))
        imageButton.tap()
        
        // Wait for image download to complete
        Thread.sleep(forTimeInterval: 4)
        
        // Verify image download was captured via setState: fallback
        verifyLogContains([
            "Fallback logging response for taskId:"
        ])
    }
}

// MARK: - How to Run
/*
 
 ## Xcode:
 1. Open Example/DemoApp.xcworkspace
 2. Select "DemoAppUITests" scheme
 3. Click ◇ next to test method
 4. Test will automatically validate logs!
 
 ## Command Line:
 ```bash
 cd Example
 xcodebuild test \
   -workspace DemoApp.xcworkspace \
   -scheme DemoAppUITests \
   -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
   -only-testing:DemoAppUITests/NetworkInstrumentationUITests/testAsyncAwaitRequest
 ```
 
 ## What These Tests Verify:
 
 ### Standard URLSession Tests
 
 ✅ testAsyncAwaitRequest:
    - SDK detects async/await context (iOS 15+)
    - FakeDelegate captures metrics
    - POST request logged with status 201
    - Validates: Async/await instrumentation
 
 ✅ testTraditionalNetworkRequest:
    - Traditional GET requests with completion handler
    - Should NOT detect as async/await
    - Request logged with status 200
    - Validates: Standard URLSession instrumentation
 
 ✅ testFailingNetworkRequest:
    - HTTP error responses captured (404)
    - Request logged with status 404
    - Validates: Error handling
 
 ✅ testPostRequest:
    - Traditional POST with completion handler
    - Request logged with status 201
    - Validates: POST method instrumentation
 
 ✅ testGetRequest:
    - Traditional GET with completion handler
    - Request logged with status 200
    - Validates: GET method instrumentation
 
 ### Third-Party Library Tests (Hybrid Approach - setState: Fallback)
 
 ✅ testAlamofireRequest:
    - Alamofire GET request
    - Captured via setState: fallback
    - Request logged with status 200
    - Validates: Alamofire success instrumentation
 
 ✅ testAlamofireFailureRequest:
    - Alamofire error request (404)
    - Captured via setState: fallback
    - Error logged with status 404
    - Validates: Alamofire error instrumentation
 
 ✅ testAlamofireUploadRequest:
    - Alamofire upload (2MB file)
    - Captured via setState: fallback
    - Upload completion logged
    - Validates: Alamofire upload instrumentation
 
 ✅ testAFNetworkingRequest:
    - Legacy AFNetworking library
    - Captured via setState: fallback
    - Request logged with status 200
    - Validates: AFNetworking instrumentation
 
 ✅ testSDWebImageDownload:
    - SDWebImage image download
    - Captured via setState: fallback
    - Download completion logged
    - Validates: Image library instrumentation
 
 ## Test Coverage Summary:
 
 | # | Test | Library | Method | Status Code | Instrumentation |
 |---|------|---------|--------|-------------|-----------------|
 | 1 | testAsyncAwaitRequest | URLSession | async/await | 201 | FakeDelegate |
 | 2 | testTraditionalNetworkRequest | URLSession | Completion | 200 | Completion wrapper |
 | 3 | testFailingNetworkRequest | URLSession | Completion | 404 | Completion wrapper |
 | 4 | testPostRequest | URLSession | Completion | 201 | Completion wrapper |
 | 5 | testGetRequest | URLSession | Completion | 200 | Completion wrapper |
 | 6 | testAlamofireRequest | Alamofire | Delegate | 200 | setState: fallback |
 | 7 | testAlamofireFailureRequest | Alamofire | Delegate | 404 | setState: fallback |
 | 8 | testAlamofireUploadRequest | Alamofire | Upload | N/A | setState: fallback |
 | 9 | testAFNetworkingRequest | AFNetworking | Delegate | 200 | setState: fallback |
 | 10 | testSDWebImageDownload | SDWebImage | Download | N/A | setState: fallback |
 
 **Total: 11 comprehensive tests covering all URLSession network instrumentation scenarios**
 
 **Note:** Flutter network requests use `setNetworkRequestContext()` API (manual reporting, 
 not URLSession instrumentation) and should be tested separately with integration tests.
 
 */
