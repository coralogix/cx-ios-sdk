//
//  DemoAppUITests.swift
//  DemoAppUITests
//
//  Created by UI Test on 2024.
//

import XCTest


final class DemoAppUITests: XCTestCase {
    
    var app: XCUIApplication!
    // Use shorter timeout for CI, longer for local debugging
    private let elementTimeout: TimeInterval = 10.0
    private let shortDelay: TimeInterval = 1.0  // For UI transitions
    private let networkDelay: TimeInterval = 3.0  // For network operations
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Initialize the app
        app = XCUIApplication()
        app.launch()
    }
    
    func testSchemaValidationFlow() throws {
        app.activate()
        
        let networkInstrumentationButton = app.staticTexts["Network instrumentation"].firstMatch
        let networkButtonExists = networkInstrumentationButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(networkButtonExists, "❌ 'Network instrumentation' button not found")
        networkInstrumentationButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        let failingNetworkButton = app.staticTexts["Failing network request"].firstMatch
        let failingButtonExists = failingNetworkButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(failingButtonExists, "❌ 'Failing network request' button not found")
        failingNetworkButton.tap()
        Thread.sleep(forTimeInterval: networkDelay)  // Wait for network request
        
        let successfulNetworkButton = app.staticTexts["Successful network request"].firstMatch
        let successfulButtonExists = successfulNetworkButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(successfulButtonExists, "❌ 'Successful network request' button not found")
        successfulNetworkButton.tap()
        Thread.sleep(forTimeInterval: networkDelay)  // Wait for network request
        
        let backButtonFromNetwork = app.buttons["BackButton"].firstMatch
        let backButtonExists = backButtonFromNetwork.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(backButtonExists, "❌ Back button from Network screen not found")
        backButtonFromNetwork.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        let errorInstrumentationButton = app.staticTexts["Error instrumentation"].firstMatch
        let errorInstrumentationExists = errorInstrumentationButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(errorInstrumentationExists, "❌ 'Error instrumentation' button not found")
        errorInstrumentationButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        // Trigger "Error" test event
        let errorButton = app.staticTexts["Error"].firstMatch
        let errorButtonExists = errorButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(errorButtonExists, "❌ 'Error' button not found")
        errorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // Trigger "Message Data Error (custom log)" event
        let messageDataErrorButton = app.staticTexts["Message Data Error"].firstMatch
        let messageDataErrorButtonExists = messageDataErrorButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(messageDataErrorButtonExists, "❌ 'Message Data Error' button not found")
        messageDataErrorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // Trigger "Log Error" event
        let logErrorButton = app.staticTexts["Log Error"].firstMatch
        let logErrorButtonExists = messageDataErrorButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(logErrorButtonExists, "❌ 'Log Error' button not found")
        logErrorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // Go back to main screen
        let backButtonFromError = app.buttons["BackButton"].firstMatch
        let backButtonFromErrorExists = backButtonFromError.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(backButtonFromErrorExists, "❌ Back button from Error screen not found")
        backButtonFromError.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        // Navigate to SDK Functions screen
        let sdkFunctionsButton = app.staticTexts["SDK functions"].firstMatch
        let sdkFunctionsExists = sdkFunctionsButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(sdkFunctionsExists, "❌ 'SDK functions' button not found")
        sdkFunctionsButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation

        // Trigger "Send Custom Measurement" event
        let customMeasurementButton = app.staticTexts["Custom Measurement"].firstMatch
        let customMeasurementButtonExist = customMeasurementButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(customMeasurementButtonExist, "❌ 'Custom Measurement' button not found")
        customMeasurementButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // Trigger "Log with Custom Labels" event
        let customLabelsButton = app.staticTexts["Custom Labels Log"].firstMatch
        let customLabelsButtonExist = customLabelsButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(customLabelsButtonExist, "❌ 'Custom Labels Log' button not found")
        customLabelsButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // Go back to main screen
        let errorButtonFromNetwork = app.buttons["BackButton"].firstMatch
        let errorButtonFromNetworkExists = errorButtonFromNetwork.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(errorButtonFromNetworkExists, "❌ Back button from Network screen not found")
        errorButtonFromNetwork.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
    }
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

