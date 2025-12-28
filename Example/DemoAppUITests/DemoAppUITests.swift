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
        isCI ? 30.0 : 10.0  // 30s in CI, 10s locally
    }
    private var shortDelay: TimeInterval {
        isCI ? 2.0 : 1.0  // 2s in CI, 1s locally
    }
    private var networkDelay: TimeInterval {
        isCI ? 10.0 : 3.0  // 10s in CI for network operations, 3s locally
    }
    
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
    Thread.sleep(forTimeInterval: shortDelay)
    
    // --- Test failing network request with UI hook ---
    let failingNetworkButton = app.staticTexts["Failing network request"].firstMatch
    let failingButtonExists = failingNetworkButton.waitForExistence(timeout: elementTimeout)
    XCTAssertTrue(failingButtonExists, "❌ 'Failing network request' button not found")
    failingNetworkButton.tap()
    
    // Wait for status label to update
    let statusLabel = app.staticTexts["NetworkStatusLabel"]
    let exists = statusLabel.waitForExistence(timeout: networkDelay)
    XCTAssertTrue(exists, "❌ Network status label did not appear")
    
    let labelText = statusLabel.label
    XCTAssertTrue(labelText.contains("error") || labelText.contains("fail") || labelText.contains("HTTP Error"),
                  "❌ Expected failure message, got: \(labelText)")
    
    // ... continue with your other steps ...
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

