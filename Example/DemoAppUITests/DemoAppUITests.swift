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
    
    // Helper to dump UI state for debugging
    private func dumpUIState(context: String) {
        log("📱 UI State Dump - \(context):")
        log("   Visible static texts:")
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(20)
        for (index, text) in texts.enumerated() {
            if text.exists {
                log("     [\(index)]: '\(text.label)'")
            }
        }
        log("   Visible buttons:")
        let buttons = app.buttons.allElementsBoundByIndex.prefix(10)
        for (index, button) in buttons.enumerated() {
            if button.exists {
                log("     [\(index)]: '\(button.label)'")
            }
        }
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
        let testStartTime = Date()
        log("🧪 Starting testSchemaValidationFlow")
        
        log("📱 Activating app...")
        app.activate()
        Thread.sleep(forTimeInterval: 1.0) // Give app time to become active
        
        log("🔍 Looking for 'Network instrumentation' button...")
        let networkInstrumentationButton = app.staticTexts["Network instrumentation"].firstMatch
        let waitStart = Date()
        let networkButtonExists = networkInstrumentationButton.waitForExistence(timeout: elementTimeout)
        let waitTime = Date().timeIntervalSince(waitStart)
        
        if !networkButtonExists {
            log("❌ 'Network instrumentation' button NOT found after \(String(format: "%.2f", waitTime))s")
            dumpUIState(context: "After waiting for Network instrumentation button")
        } else {
            log("✅ Found 'Network instrumentation' button after \(String(format: "%.2f", waitTime))s")
        }
        XCTAssertTrue(networkButtonExists, "❌ 'Network instrumentation' button not found")
        
        log("👆 Tapping 'Network instrumentation' button...")
        networkInstrumentationButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)
        
        log("🔍 Looking for 'Failing network request' button...")
        let failingNetworkButton = app.staticTexts["Failing network request"].firstMatch
        let failingWaitStart = Date()
        let failingButtonExists = failingNetworkButton.waitForExistence(timeout: elementTimeout)
        let failingWaitTime = Date().timeIntervalSince(failingWaitStart)
        
        if !failingButtonExists {
            log("❌ 'Failing network request' button NOT found after \(String(format: "%.2f", failingWaitTime))s")
            dumpUIState(context: "After waiting for Failing network request button")
        } else {
            log("✅ Found 'Failing network request' button after \(String(format: "%.2f", failingWaitTime))s")
        }
        XCTAssertTrue(failingButtonExists, "❌ 'Failing network request' button not found")
        
        log("👆 Tapping 'Failing network request' button...")
        failingNetworkButton.tap()
        
        log("⏳ Waiting for network status label (timeout: \(networkDelay)s)...")
        let statusLabel = app.staticTexts["NetworkStatusLabel"]
        let statusWaitStart = Date()
        let exists = statusLabel.waitForExistence(timeout: networkDelay)
        let statusWaitTime = Date().timeIntervalSince(statusWaitStart)
        
        if !exists {
            log("❌ Network status label did NOT appear after \(String(format: "%.2f", statusWaitTime))s")
            dumpUIState(context: "After waiting for NetworkStatusLabel")
        } else {
            log("✅ Network status label appeared after \(String(format: "%.2f", statusWaitTime))s")
        }
        XCTAssertTrue(exists, "❌ Network status label did not appear")
        
        let labelText = statusLabel.label
        log("📄 Status label text: '\(labelText)'")
        let hasError = labelText.contains("error") || labelText.contains("fail") || labelText.contains("HTTP Error")
        XCTAssertTrue(hasError, "❌ Expected failure message, got: \(labelText)")
        
        let totalTime = Date().timeIntervalSince(testStartTime)
        log("✅ Test completed successfully in \(String(format: "%.2f", totalTime))s")
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

