//
//  DemoAppUITests.swift
//  DemoAppUITests
//
//  Created by UI Test on 2024.
//

import XCTest


final class DemoAppUITests: XCTestCase {

    var app: XCUIApplication!
    private let delay: TimeInterval = 2.0

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
        XCTAssertTrue(networkInstrumentationButton.waitForExistence(timeout: delay), "❌ 'Network instrumentation' button not found")
        networkInstrumentationButton.tap()
        Thread.sleep(forTimeInterval: delay)

        // Send failiure network
        let failingNetworkButton = app.staticTexts["Failing network request"].firstMatch
        XCTAssertTrue(failingNetworkButton.waitForExistence(timeout: delay), "❌ 'Failing network request' button not found")
        failingNetworkButton.tap()
        Thread.sleep(forTimeInterval: delay)

        let successfulNetworkButton = app.staticTexts["Successful network request"].firstMatch
        XCTAssertTrue(successfulNetworkButton.waitForExistence(timeout: delay), "❌ 'Successful network request' button not found")
        successfulNetworkButton.tap()
        Thread.sleep(forTimeInterval: delay)

        // Go back to main screen from Network
        let backButtonFromNetwork = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(backButtonFromNetwork.waitForExistence(timeout: delay), "❌ Back button from Network screen not found")
        backButtonFromNetwork.tap()
        Thread.sleep(forTimeInterval: delay)

        // Navigate to Error Instrumentation screen
        let errorInstrumentationButton = app.staticTexts["Error instrumentation"].firstMatch
        XCTAssertTrue(errorInstrumentationButton.waitForExistence(timeout: delay), "❌ 'Error instrumentation' button not found")
        errorInstrumentationButton.tap()
        Thread.sleep(forTimeInterval: delay)
        
        // Trigger "Error" test event
        let errorButton = app.staticTexts["Error"].firstMatch
        XCTAssertTrue(errorButton.waitForExistence(timeout: delay), "❌ 'Error' button not found")
        errorButton.tap()
        Thread.sleep(forTimeInterval: delay)
        
        // Trigger "Stack Trace Error" test event
//        let stackTraceErrorButton = app.staticTexts["Stack Trace Error"].firstMatch
//        XCTAssertTrue(stackTraceErrorButton.waitForExistence(timeout: delay), "❌ 'Stack Trace Error' button not found")
//        stackTraceErrorButton.tap()
//        Thread.sleep(forTimeInterval: delay)
        
        // Trigger "Message Data Error (custom log)" event
        let messageDataErrorButton = app.staticTexts["Message Data Error"].firstMatch
        XCTAssertTrue(messageDataErrorButton.waitForExistence(timeout: delay), "❌ 'Message Data Error' button not found")
        messageDataErrorButton.tap()
        Thread.sleep(forTimeInterval: delay)
        
        // Trigger "Log Error" event
        let logErrorButton = app.staticTexts["Log Error"].firstMatch
        XCTAssertTrue(logErrorButton.waitForExistence(timeout: delay), "❌ 'Log Error' button not found")
        logErrorButton.tap()
        Thread.sleep(forTimeInterval: delay)
        
        // Go back to main screen
        let backButtonFromError = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(backButtonFromError.waitForExistence(timeout: delay), "❌ Back button from Error screen not found")
        backButtonFromError.tap()
        Thread.sleep(forTimeInterval: delay)

        // Navigate to SDK Functions screen
        let sdkFunctionsButton = app.staticTexts["SDK functions"].firstMatch
        XCTAssertTrue(sdkFunctionsButton.waitForExistence(timeout: delay), "❌ 'SDK functions' button not found")
        sdkFunctionsButton.tap()
        Thread.sleep(forTimeInterval: delay)
        
        // Trigger "Send Custom Measurement" event
        let customMeasurementButton = app.staticTexts["Custom Measurement"].firstMatch
        XCTAssertTrue(customMeasurementButton.waitForExistence(timeout: delay), "❌ 'Custom Measurement' button not found")
        customMeasurementButton.tap()
        Thread.sleep(forTimeInterval: delay)
        
        // Trigger "Log with Custom Labels" event
        let customLabelsButton = app.staticTexts["Custom Labels Log"].firstMatch
        XCTAssertTrue(customLabelsButton.waitForExistence(timeout: delay), "❌ 'Custom Labels Log' button not found")
        customLabelsButton.tap()
        Thread.sleep(forTimeInterval: delay)
        
        let backButtonFromSDK = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(backButtonFromSDK.waitForExistence(timeout: delay), "❌ Back button from SDK Functions screen not found")
        backButtonFromSDK.tap()
        Thread.sleep(forTimeInterval: delay)

        // Open Schema Validation screen
        let schemaValidationCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        XCTAssertTrue(schemaValidationCell.waitForExistence(timeout: delay), "❌ 'Schema validation' button not found")
        schemaValidationCell.tap()
        Thread.sleep(forTimeInterval: delay)
        
        // Wait for Schema Validation screen to load
        let validateSchemaButton = app.buttons["Validate Schema"]
        XCTAssertTrue(validateSchemaButton.waitForExistence(timeout: delay), "❌ 'Validate Schema' button not found")
        
        // Wait 2 seconds for logs to be processed
        Thread.sleep(forTimeInterval: delay)
        
        // Tap Validate Schema button
        validateSchemaButton.tap()
        
        // Wait for validation to complete
        RunLoop.current.run(until: Date().addingTimeInterval(delay))
        
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

