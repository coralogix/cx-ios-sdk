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
        
        let errorButton = app.staticTexts["Error"].firstMatch
        let errorButtonExists = errorButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(errorButtonExists, "❌ 'Error' button not found")
        errorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        let messageDataErrorButton = app.staticTexts["Message Data Error"].firstMatch
        let messageDataErrorButtonExists = messageDataErrorButton.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(messageDataErrorButtonExists, "❌ 'Message Data Error' button not found")
        messageDataErrorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
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
        
        
        let sdkFunctionsButton = app.staticTexts["SDK functions"].firstMatch
        let sdkFunctionsCell = app.cells.containing(.staticText, identifier: "SDK functions").firstMatch
        let sdkFunctionsExists = sdkFunctionsButton.waitForExistence(timeout: elementTimeout) || sdkFunctionsCell.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(sdkFunctionsExists, "❌ 'SDK functions' button not found")
        
        if sdkFunctionsCell.exists {
            sdkFunctionsCell.tap()
        } else {
            sdkFunctionsButton.tap()
        }
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        let customMeasurementButton = app.staticTexts["Custom Measurement"].firstMatch
        XCTAssertTrue(customMeasurementButton.waitForExistence(timeout: elementTimeout), "❌ 'Custom Measurement' button not found")
        customMeasurementButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        let customLabelsButton = app.staticTexts["Custom Labels Log"].firstMatch
        XCTAssertTrue(customLabelsButton.waitForExistence(timeout: elementTimeout), "❌ 'Custom Labels Log' button not found")
        customLabelsButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        
        var backButtonFromSDK: XCUIElement?
        if let navBar = app.navigationBars.allElementsBoundByIndex.first(where: { $0.exists }) {
            let navBackButton = navBar.buttons["Back"].firstMatch
            if navBackButton.waitForExistence(timeout: 2.0) {
                backButtonFromSDK = navBackButton
            } else {
                let firstNavButton = navBar.buttons.firstMatch
                if firstNavButton.waitForExistence(timeout: 2.0) {
                    backButtonFromSDK = firstNavButton
                }
            }
        }
        if backButtonFromSDK == nil {
            let backButtonDirect = app.buttons["Back"].firstMatch
            if backButtonDirect.waitForExistence(timeout: 2.0) {
                backButtonFromSDK = backButtonDirect
            }
        }
        XCTAssertNotNil(backButtonFromSDK, "❌ Back button from SDK Functions screen not found")
        backButtonFromSDK?.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        // Open Schema Validation screen
        print("📱 Phase 4.1: Looking for 'Schema validation' button...")
        let schemaValidationCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        XCTAssertTrue(schemaValidationCell.waitForExistence(timeout: elementTimeout), "❌ 'Schema validation' button not found")
        schemaValidationCell.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        
        let validateSchemaButton = app.buttons["Validate Schema"]
        XCTAssertTrue(validateSchemaButton.waitForExistence(timeout: elementTimeout), "❌ 'Validate Schema' button not found")
        Thread.sleep(forTimeInterval: networkDelay)
        validateSchemaButton.tap()
        
        let validationTimeout: TimeInterval = isCI ? 60.0 : 30.0  // Allow up to 60 seconds in CI, 30 locally
        let startTime = Date()
        var validationComplete = false
        
        while Date().timeIntervalSince(startTime) < validationTimeout {
            // Check if validation is complete by looking for result indicators
            let allTexts = app.staticTexts.allElementsBoundByIndex
            for text in allTexts {
                let label = text.label
                if label.contains("Validation Failed") || label.contains("Validation Successful") || label.contains("Validation Complete") {
                    validationComplete = true
                    print("   Found validation result indicator: \(label)")
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
            Thread.sleep(forTimeInterval: networkDelay)
        }
        
        let allStaticTexts = app.staticTexts.allElementsBoundByIndex
        var validationFailed = false
        var failureDetails: [String] = []
        
        for label in allStaticTexts {
            let labelText = label.label
            if labelText.contains("Validation Failed") {
                validationFailed = true
                failureDetails.append(labelText)
            }
        }
        
        if validationFailed {
            for detail in failureDetails {
                print("   - \(detail)")
            }
            
            // Print all visible text views and text fields that might contain response data
            for textView in app.textViews.allElementsBoundByIndex {
                if textView.exists {
                    print("   TextView: \(textView.value as? String ?? "(empty)")")
                }
            }
            
            for textField in app.textFields.allElementsBoundByIndex {
                if textField.exists {
                    print("   TextField: \(textField.value as? String ?? "(empty)")")
                }
            }
            
            for (index, label) in allStaticTexts.enumerated() {
                if label.exists {
                    print("   [\(index)]: \(label.label)")
                }
            }
            
            XCTFail("❌ Validation Failed appeared in the UI - see console log for details")
        }
    }
}

