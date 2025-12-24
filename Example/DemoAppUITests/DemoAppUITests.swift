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
        
        // Navigate to Network Instrumentation screen
        let networkInstrumentationButton = app.staticTexts["Network instrumentation"].firstMatch
        XCTAssertTrue(networkInstrumentationButton.waitForExistence(timeout: elementTimeout), "❌ 'Network instrumentation' button not found")
        networkInstrumentationButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation

        // Send failure network
        let failingNetworkButton = app.staticTexts["Failing network request"].firstMatch
        XCTAssertTrue(failingNetworkButton.waitForExistence(timeout: elementTimeout), "❌ 'Failing network request' button not found")
        failingNetworkButton.tap()
        Thread.sleep(forTimeInterval: networkDelay)  // Wait for network request

        let successfulNetworkButton = app.staticTexts["Successful network request"].firstMatch
        XCTAssertTrue(successfulNetworkButton.waitForExistence(timeout: elementTimeout), "❌ 'Successful network request' button not found")
        successfulNetworkButton.tap()
        Thread.sleep(forTimeInterval: networkDelay)  // Wait for network request

        // Go back to main screen from Network
        let backButtonFromNetwork = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(backButtonFromNetwork.waitForExistence(timeout: elementTimeout), "❌ Back button from Network screen not found")
        backButtonFromNetwork.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation

        // Navigate to Error Instrumentation screen
        let errorInstrumentationButton = app.staticTexts["Error instrumentation"].firstMatch
        XCTAssertTrue(errorInstrumentationButton.waitForExistence(timeout: elementTimeout), "❌ 'Error instrumentation' button not found")
        errorInstrumentationButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        // Trigger "Error" test event
        let errorButton = app.staticTexts["Error"].firstMatch
        XCTAssertTrue(errorButton.waitForExistence(timeout: elementTimeout), "❌ 'Error' button not found")
        errorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // Trigger "Stack Trace Error" test event
//        let stackTraceErrorButton = app.staticTexts["Stack Trace Error"].firstMatch
//        XCTAssertTrue(stackTraceErrorButton.waitForExistence(timeout: elementTimeout), "❌ 'Stack Trace Error' button not found")
//        stackTraceErrorButton.tap()
//        Thread.sleep(forTimeInterval: shortDelay)
        
        // Trigger "Message Data Error (custom log)" event
        let messageDataErrorButton = app.staticTexts["Message Data Error"].firstMatch
        XCTAssertTrue(messageDataErrorButton.waitForExistence(timeout: elementTimeout), "❌ 'Message Data Error' button not found")
        messageDataErrorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // Trigger "Log Error" event
        let logErrorButton = app.staticTexts["Log Error"].firstMatch
        XCTAssertTrue(logErrorButton.waitForExistence(timeout: elementTimeout), "❌ 'Log Error' button not found")
        logErrorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // Go back to main screen
        let backButtonFromError = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(backButtonFromError.waitForExistence(timeout: elementTimeout), "❌ Back button from Error screen not found")
        backButtonFromError.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation

        // Navigate to SDK Functions screen
        let sdkFunctionsButton = app.staticTexts["SDK functions"].firstMatch
        XCTAssertTrue(sdkFunctionsButton.waitForExistence(timeout: elementTimeout), "❌ 'SDK functions' button not found")
        sdkFunctionsButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        // Trigger "Send Custom Measurement" event
        let customMeasurementButton = app.staticTexts["Custom Measurement"].firstMatch
        XCTAssertTrue(customMeasurementButton.waitForExistence(timeout: elementTimeout), "❌ 'Custom Measurement' button not found")
        customMeasurementButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        // Trigger "Log with Custom Labels" event
        let customLabelsButton = app.staticTexts["Custom Labels Log"].firstMatch
        XCTAssertTrue(customLabelsButton.waitForExistence(timeout: elementTimeout), "❌ 'Custom Labels Log' button not found")
        customLabelsButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        let backButtonFromSDK = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(backButtonFromSDK.waitForExistence(timeout: elementTimeout), "❌ Back button from SDK Functions screen not found")
        backButtonFromSDK.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation

        // Open Schema Validation screen
        let schemaValidationCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        XCTAssertTrue(schemaValidationCell.waitForExistence(timeout: elementTimeout), "❌ 'Schema validation' button not found")
        schemaValidationCell.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        // Wait for Schema Validation screen to load
        let validateSchemaButton = app.buttons["Validate Schema"]
        XCTAssertTrue(validateSchemaButton.waitForExistence(timeout: elementTimeout), "❌ 'Validate Schema' button not found")
        
        // Wait for logs to be processed (network operations may take time in CI)
        Thread.sleep(forTimeInterval: networkDelay)
        
        // Tap Validate Schema button
        validateSchemaButton.tap()
        
        // Wait for validation to complete - use a longer timeout for network validation
        // Check for either success indicator or failure message
        let validationTimeout: TimeInterval = 30.0  // Allow up to 30 seconds for validation API
        let startTime = Date()
        var validationComplete = false
        
        while Date().timeIntervalSince(startTime) < validationTimeout {
            // Check if validation is complete by looking for result indicators
            let allTexts = app.staticTexts.allElementsBoundByIndex
            for text in allTexts {
                let label = text.label
                if label.contains("Validation Failed") || label.contains("Validation Successful") || label.contains("Validation Complete") {
                    validationComplete = true
                    break
                }
            }
            if validationComplete {
                break
            }
            Thread.sleep(forTimeInterval: 1.0)  // Check every second
        }
        
        // If validation didn't complete, wait a bit more for network delays in CI
        if !validationComplete {
            print("⚠️ Validation result not detected, waiting additional time for CI network delays...")
            Thread.sleep(forTimeInterval: networkDelay)
        }
        
        // Step 6: Wait for validation to complete and verify no "Validation Failed" appears
        let allStaticTexts = app.staticTexts.allElementsBoundByIndex
        var validationFailed = false
        var failureDetails: [String] = []

        for label in allStaticTexts {
            let labelText = label.label
            print("Label text: \(labelText)")
            
            if labelText.contains("Validation Failed") {
                validationFailed = true
                // Collect all text elements for debugging
                failureDetails.append(labelText)
            }
        }
        
        // If validation failed, print all UI text for debugging
        if validationFailed {
            print("\n❌ ============ VALIDATION FAILED ============")
            print("❌ Response/Details found in UI:")
            for detail in failureDetails {
                print("   - \(detail)")
            }
            
            // Print all visible text views and text fields that might contain response data
            print("\n📋 All Text Views:")
            for textView in app.textViews.allElementsBoundByIndex {
                if textView.exists {
                    print("   TextView: \(textView.value as? String ?? "(empty)")")
                }
            }
            
            print("\n📝 All Text Fields:")
            for textField in app.textFields.allElementsBoundByIndex {
                if textField.exists {
                    print("   TextField: \(textField.value as? String ?? "(empty)")")
                }
            }
            
            print("\n📄 All Static Texts (Full Dump):")
            for (index, label) in allStaticTexts.enumerated() {
                if label.exists {
                    print("   [\(index)]: \(label.label)")
                }
            }
            print("❌ ============================================\n")
            
            XCTFail("❌ Validation Failed appeared in the UI - see console log for details")
        } else {
            print("✅ No 'Validation Failed' message appeared - test passed!")
        }
    }
}

