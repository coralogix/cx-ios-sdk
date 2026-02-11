//
//  NetworkInstrumentationUITests.swift
//  DemoAppUITests
//
//  Created by Coralogix DEV TEAM on 05/02/2026.
//
//  These UI tests trigger network requests in the DemoApp and verify
//  that instrumentation works by validating against the Coralogix backend schema.
//
//  APPROACH: End-to-End validation using SchemaValidationViewController
//  - Trigger all network requests
//  - SDK sends data to Coralogix backend
//  - Validate schema compliance + specific status codes
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
        
        // Clear previous validation data
        clearValidationData()
    }
    
    // MARK: - Helper Methods
    
    private func clearValidationData() {
        let testDataPath = "/tmp/coralogix_validation_response.json"
        try? FileManager.default.removeItem(atPath: testDataPath)
    }
    
    private func navigateToNetworkInstrumentation() {
        print("🧭 Navigating to Network instrumentation...")
        let networkButton = app.staticTexts["Network instrumentation"]
        XCTAssertTrue(networkButton.waitForExistence(timeout: 15), "Network instrumentation button should exist")
        networkButton.tap()
        Thread.sleep(forTimeInterval: 2)
        
        // Verify we're on the network instrumentation screen
        let asyncButton = app.staticTexts["Async/Await example"]
        XCTAssertTrue(asyncButton.waitForExistence(timeout: 5), "Should be on network instrumentation screen")
        print("✅ Successfully navigated to Network instrumentation")
    }
    
    private func navigateBackToMainMenu() {
        print("🧭 Navigating back to main menu...")
        
        // Try back button first
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists {
            backButton.tap()
            Thread.sleep(forTimeInterval: 2)
            
            // Verify we're back on main menu
            let schemaButton = app.staticTexts["Verify schema"]
            if schemaButton.waitForExistence(timeout: 5) {
                print("✅ Successfully navigated back to main menu")
                return
            }
        }
        
        // Fallback: Try tapping back multiple times
        print("⚠️ First back attempt failed, trying alternative navigation...")
        for _ in 0..<3 {
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }
        
        let schemaButton = app.staticTexts["Verify schema"]
        XCTAssertTrue(schemaButton.waitForExistence(timeout: 5), "Should be back on main menu")
        print("✅ Successfully navigated back to main menu (fallback)")
    }
    
    private func navigateToSchemaValidation() {
        print("🧭 Navigating to Schema validation...")
        let schemaButton = app.staticTexts["Verify schema"]
        XCTAssertTrue(schemaButton.waitForExistence(timeout: 10), "Schema validation button should exist")
        schemaButton.tap()
        Thread.sleep(forTimeInterval: 2)
        
        // Verify we're on schema validation screen
        let validateButton = app.buttons["Validate Schema"]
        XCTAssertTrue(validateButton.waitForExistence(timeout: 5), "Should be on schema validation screen")
        print("✅ Successfully navigated to Schema validation")
    }
    
    private func triggerValidation() {
        print("🔍 Triggering validation...")
        let validateButton = app.buttons["Validate Schema"]
        XCTAssertTrue(validateButton.waitForExistence(timeout: 10), "Validate button should exist")
        
        // Ensure button is enabled before tapping
        XCTAssertTrue(validateButton.isEnabled, "Validate button should be enabled")
        validateButton.tap()
        
        // Wait for validation to complete (backend needs time to fetch and validate logs)
        print("⏳ Waiting for backend validation (15 seconds)...")
        Thread.sleep(forTimeInterval: 15)
        
        print("✅ Validation request completed")
    }
    
    private func tapNetworkOption(_ optionName: String, waitTime: TimeInterval = 2.5) {
        print("📡 Triggering: \(optionName)")
        let button = app.staticTexts[optionName]
        
        if !button.waitForExistence(timeout: 5) {
            print("⚠️ Button '\(optionName)' not found, scrolling...")
            // Try scrolling to find the button
            app.tables.firstMatch.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        
        XCTAssertTrue(button.exists, "Button '\(optionName)' should exist")
        button.tap()
        print("   ✓ Tapped '\(optionName)', waiting \(waitTime)s...")
        Thread.sleep(forTimeInterval: waitTime)
    }
    
    private func verifySchemaValidationPassed(file: StaticString = #file, line: UInt = #line) {
        print("🔍 Checking validation result...")
        
        let successMessage = "All logs are valid! ✅"
        let statusLabel = app.staticTexts[successMessage]
        
        // Wait a bit longer for status to update
        if !statusLabel.waitForExistence(timeout: 5) {
            // Capture failure details
            print("\n❌ SCHEMA VALIDATION FAILED!")
            let allLabels = app.staticTexts.allElementsBoundByIndex.map { $0.label }
            print("📋 All status labels found:")
            for label in allLabels {
                if label.contains("Validation") || label.contains("Failed") || label.contains("Error") || 
                   label.contains("logs") || label.contains("Session") {
                    print("   - \(label)")
                }
            }
            XCTFail("Schema validation failed. Check backend logs for details.", file: file, line: line)
        } else {
            print("✅ Schema validation passed!")
        }
    }
    
    private func readValidationData() -> [[String: Any]]? {
        let testDataPath = "/tmp/coralogix_validation_response.json"
        
        guard FileManager.default.fileExists(atPath: testDataPath),
              let jsonData = try? Data(contentsOf: URL(fileURLWithPath: testDataPath)),
              let validationData = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            print("❌ Failed to read validation response data")
            return nil
        }
        
        print("\n📊 Read \(validationData.count) log entries from validation response")
        return validationData
    }
    
    private func verifyRequestInValidationData(
        validationData: [[String: Any]],
        urlPattern: String,
        expectedStatusCode: Int,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        for logEntry in validationData {
            // Try to extract network request context from different possible locations
            var networkContext: [String: Any]?
            
            // Check top-level network_request_context
            if let context = logEntry["network_request_context"] as? [String: Any] {
                networkContext = context
            }
            // Check if it's nested in another structure
            else if let body = logEntry["body"] as? [String: Any],
                    let context = body["network_request_context"] as? [String: Any] {
                networkContext = context
            }
            
            guard let context = networkContext,
                  let url = context["url"] as? String else {
                continue
            }
            
            // Extract status code (could be Int or String)
            var statusCode: Int?
            if let code = context["status_code"] as? Int {
                statusCode = code
            } else if let codeString = context["status_code"] as? String,
                      let code = Int(codeString) {
                statusCode = code
            }
            
            // Check if URL contains pattern and status code matches
            if url.contains(urlPattern), let code = statusCode, code == expectedStatusCode {
                print("✅ Found: \(urlPattern) with status \(expectedStatusCode)")
                return true
            }
        }
        return false
    }
    
    private func verifyExpectedRequests(
        _ expectedRequests: [(url: String, statusCode: Int, description: String)],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let validationData = readValidationData() else {
            XCTFail("Failed to read validation data", file: file, line: line)
            return
        }
        
        print("\n🔍 Verifying \(expectedRequests.count) expected requests...")
        
        var allFound = true
        for expectedRequest in expectedRequests {
            let found = verifyRequestInValidationData(
                validationData: validationData,
                urlPattern: expectedRequest.url,
                expectedStatusCode: expectedRequest.statusCode
            )
            
            if !found {
                print("❌ Missing: \(expectedRequest.description) - \(expectedRequest.url) with status \(expectedRequest.statusCode)")
                allFound = false
            }
        }
        
        if !allFound {
            // Print all URLs found in validation data for debugging
            print("\n📋 All URLs found in validation data:")
            for (index, logEntry) in validationData.enumerated() {
                if let context = logEntry["network_request_context"] as? [String: Any],
                   let url = context["url"] as? String,
                   let statusCode = context["status_code"] {
                    print("   [\(index)] \(url) -> \(statusCode)")
                }
            }
            
            XCTFail("Some expected requests were not found in validation data", file: file, line: line)
        } else {
            print("✅ All expected requests verified!")
        }
    }
    
    // MARK: - Test Cases
    
    /// Comprehensive test: Trigger all network requests and validate via backend schema
    /// This is the main E2E test that validates the full instrumentation pipeline
    func testAllNetworkInstrumentationWithSchemaValidation() throws {
        print("\n========================================")
        print("🧪 TEST: All Network Instrumentation (E2E)")
        print("========================================\n")
        
        navigateToNetworkInstrumentation()
        
        print("\n📡 Phase 1: Triggering network requests...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        
        // 1. Async/Await request
        tapNetworkOption("Async/Await example", waitTime: 3)
        
        // 2. Traditional successful network request
        tapNetworkOption("Successful network request", waitTime: 2.5)
        
        // 3. Failing network request
        tapNetworkOption("Failing network request", waitTime: 2.5)
        
        // 4. POST request
        tapNetworkOption("POST request", waitTime: 2.5)
        
        // 5. GET request
        tapNetworkOption("GET request", waitTime: 2.5)
        
        // 6. Alamofire success
        tapNetworkOption("Alamofire success", waitTime: 3)
        
        // 7. Alamofire failure
        tapNetworkOption("Alamofire failure", waitTime: 3)
        
        // 8. Alamofire upload (takes longer)
        tapNetworkOption("Alamofire upload", waitTime: 5)
        
        // 9. AFNetworking
        tapNetworkOption("AFNetworking request", waitTime: 3)
        
        // Wait for SDK to batch and send all data to backend
        print("\n⏳ Phase 2: Waiting for SDK to send data to backend (8 seconds)...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        Thread.sleep(forTimeInterval: 8)
        
        // Navigate to schema validation
        print("🔍 Phase 3: Validating schema...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        navigateBackToMainMenu()
        navigateToSchemaValidation()
        
        // Trigger validation
        triggerValidation()
        
        // Verify schema validation passed
        verifySchemaValidationPassed()
        
        // Verify specific requests and status codes
        print("\n🔎 Phase 4: Verifying specific requests...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        let expectedRequests: [(url: String, statusCode: Int, description: String)] = [
            ("jsonplaceholder.typicode.com/posts", 201, "Async/Await POST"),
            ("jsonplaceholder.typicode.com/posts", 200, "Successful GET"),
            ("jsonplaceholder.typicode.com/posts1", 404, "Failing GET"),
            ("jsonplaceholder.typicode.com/posts", 201, "POST request"),
            ("jsonplaceholder.typicode.com/posts/1", 200, "GET request"),
            ("jsonplaceholder.typicode.com/posts", 200, "Alamofire success"),
            ("jsonplaceholder.typicode.com/posts1", 404, "Alamofire failure"),
            ("api.escuelajs.co/api/v1/files/upload", 201, "Alamofire upload"),
            ("jsonplaceholder.typicode.com/posts", 200, "AFNetworking")
        ]
        
        verifyExpectedRequests(expectedRequests)
        
        print("\n✅ SUCCESS: All network instrumentation validated end-to-end!")
        print("========================================\n")
    }
    
    /// Quick smoke test: Single request to verify instrumentation is working
    func testQuickSmokeTest() throws {
        print("\n========================================")
        print("🧪 TEST: Quick Smoke Test")
        print("========================================\n")
        
        navigateToNetworkInstrumentation()
        
        tapNetworkOption("Async/Await example", waitTime: 3)
        
        print("\n⏳ Waiting for SDK to send data (5 seconds)...")
        Thread.sleep(forTimeInterval: 5)
        
        print("\n🔍 Validating...")
        navigateBackToMainMenu()
        navigateToSchemaValidation()
        triggerValidation()
        
        verifySchemaValidationPassed()
        
        // Verify at least one request was captured
        guard let validationData = readValidationData() else {
            XCTFail("Failed to read validation data")
            return
        }
        
        XCTAssertTrue(validationData.count > 0, "Should have at least one log entry")
        print("✅ Smoke test passed: \(validationData.count) log entries found")
        print("========================================\n")
    }
    
    /// Navigation test: Verify app navigation works without crashes
    func testNavigationOnly() throws {
        print("\n========================================")
        print("🧪 TEST: Navigation Test (No Requests)")
        print("========================================\n")
        
        print("🧭 Testing navigation flow...")
        
        // Navigate to network instrumentation
        navigateToNetworkInstrumentation()
        print("✅ Network instrumentation screen loaded")
        
        // Navigate back
        navigateBackToMainMenu()
        print("✅ Back to main menu")
        
        // Navigate to schema validation
        navigateToSchemaValidation()
        print("✅ Schema validation screen loaded")
        
        print("\n✅ SUCCESS: Navigation test passed!")
        print("========================================\n")
    }
}

// MARK: - How to Run
/*
 
 ## Xcode:
 1. Open Example/DemoApp.xcworkspace
 2. Select "DemoAppUITests" scheme
 3. Click ◇ next to test method
 4. Test will automatically validate against backend!
 
 ## Command Line:
 ```bash
 cd Example
 xcodebuild test \
   -workspace DemoApp.xcworkspace \
   -scheme DemoAppUITests \
   -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
   -only-testing:DemoAppUITests/NetworkInstrumentationUITests/testAllNetworkInstrumentationWithSchemaValidation
 ```
 
 ## What This Test Validates:
 
 ### End-to-End Validation Approach
 
 ✅ **testAllNetworkInstrumentationWithSchemaValidation**:
    - Triggers ALL network request types
    - Waits for SDK to send data to Coralogix backend
    - Validates via SchemaValidationViewController
    - Checks:
      1. ✅ Schema validation passes (all logs conform to Coralogix schema)
      2. ✅ Each request has correct HTTP status code
      3. ✅ Data actually reaches backend (not just local logging)
 
 ### Coverage:
 
 | # | Request Type | Library | Method | Expected Status | Validation |
 |---|-------------|---------|--------|-----------------|------------|
 | 1 | Async/Await POST | URLSession | async/await | 201 | Backend schema |
 | 2 | Successful GET | URLSession | Completion | 200 | Backend schema |
 | 3 | Failing GET | URLSession | Completion | 404 | Backend schema |
 | 4 | POST request | URLSession | Completion | 201 | Backend schema |
 | 5 | GET request | URLSession | Completion | 200 | Backend schema |
 | 6 | Alamofire success | Alamofire | Delegate | 200 | Backend schema |
 | 7 | Alamofire failure | Alamofire | Delegate | 404 | Backend schema |
 | 8 | Alamofire upload | Alamofire | Upload | 201 | Backend schema |
 | 9 | AFNetworking | AFNetworking | Delegate | 200 | Backend schema |
 
 ### Benefits of This Approach:
 
 ✅ **True E2E Testing**: Validates actual network flow from device to backend
 ✅ **Schema Compliance**: Ensures logs match Coralogix schema requirements
 ✅ **Production-like**: Tests real backend integration, not just local mocks
 ✅ **Comprehensive**: Single test validates all instrumentation types
 ✅ **Reliable**: No file I/O, no timing issues with log parsing
 
 ### Notes:
 
 - **Flutter requests** use `setNetworkRequestContext()` (manual API, not URLSession)
   and should be tested separately with integration tests
 
 - **SDWebImage** is excluded as the image URL may redirect/fail in test environments
 
 - Test requires backend to be available at proxy URL specified in envs.swift
 
 */
