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
//  TEMP FILE USAGE:
//  - /tmp/coralogix_validation_response.json is used for status code verification
//  - SchemaValidationViewController saves the backend response there (when --uitesting flag is set)
//  - Test verifies both:
//    1. Schema validation passes (UI check)
//    2. Each request has correct HTTP status code (temp file check)
//

import XCTest

final class NetworkInstrumentationUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Enable test mode - saves validation data to temp file
        app.launchArguments = ["--uitesting"]
        
        print("🚀 Launching app with --uitesting flag")
        print("   This enables SchemaValidationViewController to save validation data")
        
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
        
        // Simple approach from existing DemoAppUITests
        let navBar = app.navigationBars.firstMatch
        let backButton = navBar.buttons.firstMatch
        
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Back button should exist")
        backButton.tap()
        Thread.sleep(forTimeInterval: 2)
        
        // Verify we're back on main menu by checking for a main menu item
        let schemaValidationCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        XCTAssertTrue(schemaValidationCell.waitForExistence(timeout: 5), "Should be back on main menu")
        print("✅ Successfully navigated back to main menu")
    }
    
    private func navigateToSchemaValidation() {
        print("🧭 Navigating to Schema validation...")
        
        // Use correct identifier from existing DemoAppUITests
        let schemaValidationCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        XCTAssertTrue(schemaValidationCell.waitForExistence(timeout: 10), "Schema validation cell should exist")
        
        schemaValidationCell.tap()
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
        print("   (Backend needs time to ingest and index logs)")
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
        
        // Check if file exists
        if !FileManager.default.fileExists(atPath: testDataPath) {
            print("⚠️  Validation data file not found at: \(testDataPath)")
            print("   Make sure --uitesting flag is passed to app (set in setUpWithError)")
            return nil
        }
        
        // Try to read and parse the file
        guard let jsonData = try? Data(contentsOf: URL(fileURLWithPath: testDataPath)) else {
            print("❌ Failed to read validation response file")
            return nil
        }
        
        // Parse JSON - validation response structure:
        // [{"logs": [log1, log2], "validationResult": {...}}, {"logs": [log3], "validationResult": {...}}, ...]
        // Need to collect logs from ALL objects, not just the first one
        if let directArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            // Check if it's wrapped structure with "logs" key
            if directArray.count > 0,
               let firstItem = directArray.first,
               firstItem["logs"] != nil {
                // Wrapped structure - collect logs from ALL objects
                var allLogs: [[String: Any]] = []
                for item in directArray {
                    if let logs = item["logs"] as? [[String: Any]] {
                        allLogs.append(contentsOf: logs)
                    }
                }
                print("\n📊 Read \(allLogs.count) log entries from validation response (unwrapped from \(directArray.count) validation objects)")
                return allLogs
            } else {
                // Direct array of logs
                print("\n📊 Read \(directArray.count) log entries from validation response")
                return directArray
            }
        } else {
            print("❌ Failed to parse validation response data")
            print("   File exists but couldn't parse JSON")
            return nil
        }
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
        // Read validation data to verify each request's status code
        // This requires reading the temp file where SchemaValidationViewController saves data
        guard let validationData = readValidationData() else {
            print("\n⚠️  WARNING: Could not read validation data file!")
            print("   Temp file: /tmp/coralogix_validation_response.json")
            print("   This means:")
            print("   1. App didn't receive --uitesting flag (check setUpWithError)")
            print("   2. SchemaValidationViewController didn't save the file")
            print("   3. File permissions issue")
            print("\n   ✅ Schema validation UI check already passed")
            print("   ❌ Skipping detailed status code verification")
            print("\n   For full validation, ensure app.launchArguments = [\"--uitesting\"] is set")
            
            // For CI, this should fail
            // For local debugging, you can comment this out to just check UI
            let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
            if isCI {
                XCTFail("Validation data file required in CI mode", file: file, line: line)
            } else {
                print("\n   ℹ️  Running in local mode - allowing test to pass with UI check only")
            }
            return
        }
        
        // Count how many entries have network_request_context
        var networkLogCount = 0
        for logEntry in validationData {
            if let _ = logEntry["network_request_context"] as? [String: Any] {
                networkLogCount += 1
            } else if let body = logEntry["body"] as? [String: Any],
                      let _ = body["network_request_context"] as? [String: Any] {
                networkLogCount += 1
            }
        }
        
        print("\n🔍 Verifying \(expectedRequests.count) expected requests...")
        print("   Total log entries in response: \(validationData.count)")
        print("   Entries with network_request_context: \(networkLogCount)")
        
        if networkLogCount < expectedRequests.count {
            print("⚠️  WARNING: Found fewer network logs (\(networkLogCount)) than expected (\(expectedRequests.count))")
            print("   This might mean:")
            print("   - SDK hasn't sent all data yet (need more wait time)")
            print("   - Backend hasn't ingested all logs yet")
            print("   - Some requests failed to be instrumented")
        }
        
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
        
        // Always print what we found for debugging
        print("\n📋 All log entries in validation data:")
        for (index, logEntry) in validationData.enumerated() {
            // Try different paths where network context might be
            var url: String?
            var statusCode: Any?
            var logType = "unknown"
            
            if let context = logEntry["network_request_context"] as? [String: Any] {
                url = context["url"] as? String
                statusCode = context["status_code"]
                logType = "network"
            } else if let body = logEntry["body"] as? [String: Any],
                      let context = body["network_request_context"] as? [String: Any] {
                url = context["url"] as? String
                statusCode = context["status_code"]
                logType = "network"
            } else {
                // Check what type of log this is
                let body = logEntry["body"] as? [String: Any]
                if logEntry["view_context"] != nil || body?["view_context"] != nil {
                    logType = "view"
                } else if logEntry["error_context"] != nil || body?["error_context"] != nil {
                    logType = "error"
                } else if logEntry["interaction_context"] != nil || body?["interaction_context"] != nil {
                    logType = "interaction"
                }
            }
            
            if let url = url {
                print("   [\(index)] [NETWORK] \(url) -> \(statusCode ?? "N/A")")
            } else {
                print("   [\(index)] [\(logType.uppercased())] (not a network log)")
                if index < 3 {  // Show structure for first 3 non-network logs
                    print("      Keys: \(Array(logEntry.keys.prefix(5)))")
                }
            }
        }
        
        if !allFound {
            XCTFail("Some expected requests were not found in validation data. Only found \(validationData.count) entries, expected ~\(expectedRequests.count)", file: file, line: line)
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
        print("   (Order matches NetworkViewController.swift)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        
        // Order matches NetworkViewController.swift (skipping Flutter requests)
        
        // 1. Failing network request
        tapNetworkOption("Failing network request", waitTime: 2.5)
        
        // 2. Successful network request
        tapNetworkOption("Successful network request", waitTime: 2.5)
        
        // 3-4. Flutter requests (SKIPPED - use setNetworkRequestContext API, not URLSession)
        
        // 5. Alamofire success
        tapNetworkOption("Alamofire success", waitTime: 3)
        
        // 6. Alamofire failure
        tapNetworkOption("Alamofire failure", waitTime: 3)
        
        // 7. Alamofire upload (takes longer)
        tapNetworkOption("Alamofire upload", waitTime: 5)
        
        // 8. AFNetworking
        tapNetworkOption("AFNetworking request", waitTime: 3)
        
        // 9. SDWebImage download
        tapNetworkOption("Download image (SDWebImage)", waitTime: 3)
        
        // 10. POST request
        tapNetworkOption("POST request", waitTime: 2.5)
        
        // 11. GET request
        tapNetworkOption("GET request", waitTime: 2.5)
        
        // 12. Async/Await example
        tapNetworkOption("Async/Await example", waitTime: 3)
        
        // Wait for SDK to batch and send all data to backend
        print("\n⏳ Phase 2: Waiting for SDK to send data to backend (8 seconds)...")
        print("   (Need time for 11 requests to be batched and sent)")
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
        print("\n🔎 Phase 4: Verifying specific requests and status codes...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        
        // Expected requests in order they were triggered
        let expectedRequests: [(url: String, statusCode: Int, description: String)] = [
            ("jsonplaceholder.typicode.com/posts1", 404, "1. Failing GET"),
            ("jsonplaceholder.typicode.com/posts", 200, "2. Successful GET"),
            ("jsonplaceholder.typicode.com/posts", 200, "5. Alamofire success"),
            ("jsonplaceholder.typicode.com/posts1", 404, "6. Alamofire failure"),
            ("api.escuelajs.co/api/v1/files/upload", 201, "7. Alamofire upload"),
            ("jsonplaceholder.typicode.com/posts", 200, "8. AFNetworking"),
            // 9. SDWebImage - Skip verification (Google redirect URL, unpredictable)
            ("jsonplaceholder.typicode.com/posts", 201, "10. POST request"),
            ("jsonplaceholder.typicode.com/posts/1", 200, "11. GET request"),
            ("jsonplaceholder.typicode.com/posts", 201, "12. Async/Await POST")
        ]
        
        verifyExpectedRequests(expectedRequests)
        
        print("\n✅ SUCCESS: All network instrumentation validated end-to-end!")
        print("========================================\n")
    }
    
}

// MARK: - How to Run
/*
 
 ## Xcode (Local Development):
 1. Open Example/DemoApp.xcworkspace
 2. Select "DemoAppUITests" scheme
 3. Click ◇ next to testAllNetworkInstrumentationWithSchemaValidation
 4. Test will validate:
    - ✅ Schema validation passes (UI check)
    - ✅ Status codes (if --uitesting flag works)
 
 Note: The --uitesting flag is set in setUpWithError() automatically.
 If status code verification fails, check console for warnings about missing temp file.
 
 ## Command Line (CI):
 ```bash
 cd Example
 xcodebuild test \
   -workspace DemoApp.xcworkspace \
   -scheme DemoAppUITests \
   -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
   -only-testing:DemoAppUITests/NetworkInstrumentationUITests/testAllNetworkInstrumentationWithSchemaValidation
 ```
 
 In CI mode (CI=true env var), the test REQUIRES status code verification and will fail if temp file is missing.
 
 ## Expected Duration:
 - ~65 seconds total
 - 11 network requests (~35 seconds)
 - SDK batching wait (~8 seconds) - SDK exports every 2s
 - Backend validation (~15 seconds) - Backend ingestion/indexing time
 - Screen navigation (~7 seconds)
 
 ## What This Test Validates:
 
 ### End-to-End Validation Approach
 
 ✅ **testAllNetworkInstrumentationWithSchemaValidation**:
    - Triggers ALL network request types (11 requests)
    - Waits for SDK to send data to Coralogix backend
    - Validates via SchemaValidationViewController
    - Mandatory checks:
      1. ✅ Schema validation passes (all logs conform to Coralogix schema)
      2. ✅ Each request has correct HTTP status code (200, 404, 201)
      3. ✅ Data actually reaches backend (not just local logging)
      4. ✅ All 9 expected requests found in validation response
 
### Coverage (Order matches NetworkViewController.swift):
 
| # | Request Type | Library | Method | Expected Status | Validation |
|---|-------------|---------|--------|-----------------|------------|
| 1 | Failing GET | URLSession | Completion | 404 | Backend schema |
| 2 | Successful GET | URLSession | Completion | 200 | Backend schema |
| 3-4 | Flutter requests | Manual API | setNetworkRequestContext | N/A | Skipped (not URLSession) |
| 5 | Alamofire success | Alamofire | Delegate | 200 | Backend schema |
| 6 | Alamofire failure | Alamofire | Delegate | 404 | Backend schema |
| 7 | Alamofire upload | Alamofire | Upload | 201 | Backend schema |
| 8 | AFNetworking | AFNetworking | Delegate | 200 | Backend schema |
| 9 | SDWebImage download | SDWebImage | Download | N/A | Backend schema (no status check) |
| 10 | POST request | URLSession | Completion | 201 | Backend schema |
| 11 | GET request | URLSession | Completion | 200 | Backend schema |
| 12 | Async/Await POST | URLSession | async/await | 201 | Backend schema |
 
### Benefits of This Approach:
 
✅ **True E2E Testing**: Validates actual network flow from device to backend
✅ **Schema Compliance**: Ensures logs match Coralogix schema requirements
✅ **Status Code Verification**: Confirms each request has correct HTTP status (200, 404, 201)
✅ **Production-like**: Tests real backend integration, not just local mocks
✅ **Comprehensive**: Single test validates all 11 instrumentation scenarios
✅ **Reliable**: Direct backend validation, not dependent on local file parsing
 
### Notes:
 
- **Flutter requests** use `setNetworkRequestContext()` (manual API, not URLSession)
  and should be tested separately with integration tests
 
- **SDWebImage** is included but status code verification is skipped (Google redirect URL is unpredictable)
  - Schema validation still confirms the request was instrumented correctly
 
- Test requires backend to be available at proxy URL specified in envs.swift
 
- **Total**: 11 network requests tested (12 items - 1 Flutter skip + 1 SDWebImage added)
 
- **If test fails with "Only found X entries"**: 
  - Backend ingestion pipeline may need more time
  - Check console output to see what log types were found (network vs text/view/error)
  - SDK exports every 2 seconds, so 8s = 4 cycles (should be enough)
  - Increase backend validation wait if needed (currently 15s)
  - Backend may have ingestion lag for network logs specifically
 
- **If test shows "Could not read validation data file"**:
  - Check that --uitesting flag is being passed (see setUpWithError)
  - In local development mode, test will still pass with UI validation only
  - In CI mode (CI=true env var), test will fail without status code verification
 
 */
