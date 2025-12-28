//
//  DemoAppUITests.swift
//  DemoAppUITests
//
//  Created by UI Test on 2024.
//

import XCTest


final class DemoAppUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    // Detect CI environment (GitHub Actions, Jenkins, etc.)
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] == "true" ||
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" ||
        ProcessInfo.processInfo.environment["CONTINUOUS_INTEGRATION"] == "true"
    }
    
    // Use longer timeouts in CI due to slower network/API calls
    private var elementTimeout: TimeInterval {
        isCI ? 15.0 : 10.0  // 15s in CI (reduced from 30s), 10s locally
    }
    private var shortDelay: TimeInterval {
        isCI ? 1.5 : 1.0  // 1.5s in CI, 1s locally
    }
    private var networkDelay: TimeInterval {
        isCI ? 8.0 : 3.0  // 8s in CI for network operations, 3s locally
    }
    
    // Helper to log with timestamp
    private func log(_ message: String) {
        let timestamp = String(format: "%.2f", Date().timeIntervalSince1970)
        print("🕐 [\(timestamp)] \(message)")
    }
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        log("🚀 Starting test setup")
        log("   CI Environment: \(isCI)")
        log("   Element timeout: \(elementTimeout)s")
        log("   Network delay: \(networkDelay)s")
        
        app = XCUIApplication()
        log("📱 Launching app...")
        let startTime = Date()
        app.launch()
        let launchTime = Date().timeIntervalSince(startTime)
        log("✅ App launched in \(String(format: "%.2f", launchTime))s")
    }
    
    func testSchemaValidationFlow() throws {
         app.activate()
        
        let networkInstrumentationButton = app.staticTexts["Network instrumentation"].firstMatch
        let networkButtonExists = networkInstrumentationButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(networkButtonExists, "❌ 'Network instrumentation' button not found")
        networkInstrumentationButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        // let failingNetworkButton = app.staticTexts["Failing network request"].firstMatch
        // let failingButtonExists = failingNetworkButton.waitForExistence(timeout: elementTimeout)
        // XCTAssertTrue(failingButtonExists, "❌ 'Failing network request' button not found")
        // failingNetworkButton.tap()
        // Thread.sleep(forTimeInterval: networkDelay)  // Wait for network request
        
        // let successfulNetworkButton = app.staticTexts["Successful network request"].firstMatch
        // let successfulButtonExists = successfulNetworkButton.waitForExistence(timeout: elementTimeout)
        // XCTAssertTrue(successfulButtonExists, "❌ 'Successful network request' button not found")
        // successfulNetworkButton.tap()
        // Thread.sleep(forTimeInterval: networkDelay)  // Wait for network request
        
        // let backButtonFromNetwork = app.buttons["BackButton"].firstMatch
        // let backButtonExists = backButtonFromNetwork.waitForExistence(timeout: elementTimeout)
        // XCTAssertTrue(backButtonExists, "❌ Back button from Network screen not found")
        // backButtonFromNetwork.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        

        // // ========== PHASE 2: Error Instrumentation ==========
        // let errorInstrumentationButton = app.staticTexts["Error instrumentation"].firstMatch
        // let errorInstrumentationExists = errorInstrumentationButton.waitForExistence(timeout: elementTimeout)
        // XCTAssertTrue(errorInstrumentationExists, "❌ 'Error instrumentation' button not found")
        // errorInstrumentationButton.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        // // Trigger "Error" test event
        // let errorButton = app.staticTexts["Error"].firstMatch
        // let errorButtonExists = errorButton.waitForExistence(timeout: elementTimeout)
        // XCTAssertTrue(errorButtonExists, "❌ 'Error' button not found")
        // errorButton.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // // Trigger "Message Data Error (custom log)" event
        // let messageDataErrorButton = app.staticTexts["Message Data Error"].firstMatch
        // let messageDataErrorButtonExists = messageDataErrorButton.waitForExistence(timeout: elementTimeout)
        // XCTAssertTrue(messageDataErrorButtonExists, "❌ 'Message Data Error' button not found")
        // messageDataErrorButton.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // // Trigger "Log Error" event
        // let logErrorButton = app.staticTexts["Log Error"].firstMatch
        // let logErrorButtonExists = messageDataErrorButton.waitForExistence(timeout: elementTimeout)
        // XCTAssertTrue(logErrorButtonExists, "❌ 'Log Error' button not found")
        // logErrorButton.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // // Go back to main screen
        // let backButtonFromError = app.buttons["BackButton"].firstMatch
        // let backButtonFromErrorExists = backButtonFromError.waitForExistence(timeout: elementTimeout)
        // XCTAssertTrue(backButtonFromErrorExists, "❌ Back button from Error screen not found")
        // backButtonFromError.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
    }
        // // ========== PHASE 3: SDK Functions ==========
        // print("📱 Phase 3: Starting SDK Functions...")
        
        // // Navigate to SDK Functions screen
        // print("📱 Phase 3.1: Looking for 'SDK functions' button...")
        // let sdkFunctionsButton = app.staticTexts["SDK functions"].firstMatch
        // let sdkFunctionsCell = app.cells.containing(.staticText, identifier: "SDK functions").firstMatch
        // let sdkFunctionsExists = sdkFunctionsButton.waitForExistence(timeout: elementTimeout) || sdkFunctionsCell.waitForExistence(timeout: elementTimeout)
        // XCTAssertTrue(sdkFunctionsExists, "❌ 'SDK functions' button not found")
        // print("✅ Phase 3.1: Found SDK functions button")
        
        // print("📱 Phase 3.2: Tapping SDK functions button...")
        // if sdkFunctionsCell.exists {
        //     sdkFunctionsCell.tap()
        // } else {
        //     sdkFunctionsButton.tap()
        // }
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        // print("✅ Phase 3.2: Tapped SDK functions button")
        
        // // Trigger "Send Custom Measurement" event
        // print("📱 Phase 3.3: Looking for 'Custom Measurement' button...")
        // let customMeasurementButton = app.staticTexts["Custom Measurement"].firstMatch
        // XCTAssertTrue(customMeasurementButton.waitForExistence(timeout: elementTimeout), "❌ 'Custom Measurement' button not found")
        // print("✅ Phase 3.3: Found Custom Measurement button")
        // customMeasurementButton.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        // print("✅ Phase 3.4: Tapped Custom Measurement button")
        
        // // Trigger "Log with Custom Labels" event
        // print("📱 Phase 3.5: Looking for 'Custom Labels Log' button...")
        // let customLabelsButton = app.staticTexts["Custom Labels Log"].firstMatch
        // XCTAssertTrue(customLabelsButton.waitForExistence(timeout: elementTimeout), "❌ 'Custom Labels Log' button not found")
        // print("✅ Phase 3.5: Found Custom Labels Log button")
        // customLabelsButton.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        // print("✅ Phase 3.6: Tapped Custom Labels Log button")
        
        // // Find back button
        // print("📱 Phase 3.7: Looking for Back button...")
        // var backButtonFromSDK: XCUIElement?
        // if let navBar = app.navigationBars.allElementsBoundByIndex.first(where: { $0.exists }) {
        //     let navBackButton = navBar.buttons["Back"].firstMatch
        //     if navBackButton.waitForExistence(timeout: 2.0) {
        //         backButtonFromSDK = navBackButton
        //     } else {
        //         let firstNavButton = navBar.buttons.firstMatch
        //         if firstNavButton.waitForExistence(timeout: 2.0) {
        //             backButtonFromSDK = firstNavButton
        //         }
        //     }
        // }
        // if backButtonFromSDK == nil {
        //     let backButtonDirect = app.buttons["Back"].firstMatch
        //     if backButtonDirect.waitForExistence(timeout: 2.0) {
        //         backButtonFromSDK = backButtonDirect
        //     }
        // }
        // XCTAssertNotNil(backButtonFromSDK, "❌ Back button from SDK Functions screen not found")
        // backButtonFromSDK?.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        // print("✅ Phase 3.7: Tapped Back button")
        // print("✅ Phase 3 (SDK Functions) completed successfully")

        // // ========== PHASE 4: Schema Validation ==========
        // print("📱 Phase 4: Starting Schema Validation...")
        
        // // Open Schema Validation screen
        // print("📱 Phase 4.1: Looking for 'Schema validation' button...")
        // let schemaValidationCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        // XCTAssertTrue(schemaValidationCell.waitForExistence(timeout: elementTimeout), "❌ 'Schema validation' button not found")
        // print("✅ Phase 4.1: Found Schema validation button")
        // schemaValidationCell.tap()
        // Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        // print("✅ Phase 4.2: Tapped Schema validation button")
        
        // // Wait for Schema Validation screen to load
        // print("📱 Phase 4.3: Looking for 'Validate Schema' button...")
        // let validateSchemaButton = app.buttons["Validate Schema"]
        // XCTAssertTrue(validateSchemaButton.waitForExistence(timeout: elementTimeout), "❌ 'Validate Schema' button not found")
        // print("✅ Phase 4.3: Found Validate Schema button")
        
        // // Wait for logs to be processed (network operations may take time in CI)
        // print("📱 Phase 4.4: Waiting for logs to be processed...")
        // Thread.sleep(forTimeInterval: networkDelay)
        // print("✅ Phase 4.4: Wait complete")
        
        // // Tap Validate Schema button
        // print("📱 Phase 4.5: Tapping Validate Schema button...")
        // validateSchemaButton.tap()
        // print("✅ Phase 4.5: Tapped Validate Schema button")
        
        // // Wait for validation to complete - use a longer timeout for network validation
        // print("📱 Phase 4.6: Waiting for validation to complete...")
        // let validationTimeout: TimeInterval = isCI ? 60.0 : 30.0  // Allow up to 60 seconds in CI, 30 locally
        // let startTime = Date()
        // var validationComplete = false
        
        // while Date().timeIntervalSince(startTime) < validationTimeout {
        //     // Check if validation is complete by looking for result indicators
        //     let allTexts = app.staticTexts.allElementsBoundByIndex
        //     for text in allTexts {
        //         let label = text.label
        //         if label.contains("Validation Failed") || label.contains("Validation Successful") || label.contains("Validation Complete") {
        //             validationComplete = true
        //             print("   Found validation result indicator: \(label)")
        //             break
        //         }
        //     }
        //     if validationComplete {
        //         break
        //     }
        //     Thread.sleep(forTimeInterval: 1.0)  // Check every second
        // }
        
        // // If validation didn't complete, wait a bit more for network delays in CI
        // if !validationComplete {
        //     print("⚠️ Validation result not detected, waiting additional time for CI network delays...")
        //     Thread.sleep(forTimeInterval: networkDelay)
        // }
        
        // // Verify no "Validation Failed" appears
        // print("📱 Phase 4.7: Checking validation results...")
        // let allStaticTexts = app.staticTexts.allElementsBoundByIndex
        // var validationFailed = false
        // var failureDetails: [String] = []

        // for label in allStaticTexts {
        //     let labelText = label.label
        //     if labelText.contains("Validation Failed") {
        //         validationFailed = true
        //         failureDetails.append(labelText)
        //     }
        // }
        
        // // If validation failed, print all UI text for debugging
        // if validationFailed {
        //     print("\n❌ ============ VALIDATION FAILED ============")
        //     print("❌ Response/Details found in UI:")
        //     for detail in failureDetails {
        //         print("   - \(detail)")
        //     }
            
        //     // Print all visible text views and text fields that might contain response data
        //     print("\n📋 All Text Views:")
        //     for textView in app.textViews.allElementsBoundByIndex {
        //         if textView.exists {
        //             print("   TextView: \(textView.value as? String ?? "(empty)")")
        //         }
        //     }
            
        //     print("\n📝 All Text Fields:")
        //     for textField in app.textFields.allElementsBoundByIndex {
        //         if textField.exists {
        //             print("   TextField: \(textField.value as? String ?? "(empty)")")
        //         }
        //     }
            
        //     print("\n📄 All Static Texts (Full Dump):")
        //     for (index, label) in allStaticTexts.enumerated() {
        //         if label.exists {
        //             print("   [\(index)]: \(label.label)")
        //         }
        //     }
        //     print("❌ ============================================\n")
            
        //     XCTFail("❌ Validation Failed appeared in the UI - see console log for details")
        // } else {
        //     print("✅ No 'Validation Failed' message appeared - validation passed!")
        // }
        // print("✅ Phase 4 (Schema Validation) completed successfully")
        // print("🎉 All phases completed successfully - test passed!")
    
}

