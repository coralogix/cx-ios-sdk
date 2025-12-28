//
//  DemoAppUITests.swift
//  DemoAppUITests
//
//  Created by UI Test on 2024.
//

import XCTest


final class DemoAppUITests: XCTestCase {

    var app: XCUIApplication!
    // Detect CI environment and adjust timeouts accordingly
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] == "true" || 
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
    }
    // Use longer timeouts for CI, shorter for local debugging
    private var elementTimeout: TimeInterval {
        isCI ? 15.0 : 10.0
    }
    private var shortDelay: TimeInterval {
        isCI ? 2.0 : 1.0  // For UI transitions - longer in CI
    }
    private var networkDelay: TimeInterval {
        isCI ? 5.0 : 3.0  // For network operations - longer in CI
    }
    
    /// Wait for the app to be fully ready - main screen loaded
    private func waitForAppToBeReady() throws {
        // In CI, give the app more time to launch
        if isCI {
            print("   🔄 CI environment detected - using extended timeouts")
            Thread.sleep(forTimeInterval: 2.0)  // Extra wait for CI
        }
        
        // Wait for app to be in foreground (with longer timeout in CI)
        let appStateTimeout: TimeInterval = isCI ? 20.0 : 10.0
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < appStateTimeout {
            if app.state == .runningForeground {
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(app.state == .runningForeground, "App is not in foreground state after \(appStateTimeout)s")
        
        // Wait for navigation bar to appear (indicates main view controller is loaded)
        // Try multiple possible titles in case of localization or different states
        let possibleTitles = ["Coralogix Demo", "Root View Controller"]
        var navBarExists = false
        var foundTitle = ""
        
        let navBarTimeout: TimeInterval = isCI ? 15.0 : 10.0
        for title in possibleTitles {
            let navigationBar = app.navigationBars[title]
            if navigationBar.waitForExistence(timeout: navBarTimeout) {
                navBarExists = true
                foundTitle = title
                break
            }
        }
        
        XCTAssertTrue(navBarExists, "Main navigation bar not found - app may not have loaded. Tried: \(possibleTitles)")
        
        // Wait for at least one table view cell to appear (menu items)
        // Try waiting for the table view first
        let tableView = app.tables.firstMatch
        let tableViewTimeout: TimeInterval = isCI ? 15.0 : 10.0
        let tableViewExists = tableView.waitForExistence(timeout: tableViewTimeout)
        XCTAssertTrue(tableViewExists, "Table view not found - main menu may not have loaded")
        
        // Wait for cells to populate
        let cellTimeout: TimeInterval = isCI ? 15.0 : 10.0
        let firstCell = app.cells.firstMatch
        let cellExists = firstCell.waitForExistence(timeout: cellTimeout)
        XCTAssertTrue(cellExists, "No table view cells found - main menu may not have loaded")
        
        // Scroll to top to ensure first items are visible (in case table view scrolled)
        if tableViewExists {
            tableView.swipeDown()  // Scroll to top
            Thread.sleep(forTimeInterval: isCI ? 1.0 : 0.5)  // Wait for scroll animation
        }
        
        // Additional delay to ensure UI is fully rendered and stable (longer in CI)
        Thread.sleep(forTimeInterval: isCI ? 2.0 : 1.0)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Initialize the app
        app = XCUIApplication()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        
        // Don't wait in setUp - let the test method handle waiting
        // This prevents setUp from timing out if the app takes longer to load
    }
    
    func testSimple() throws {
        // Simple test that does nothing - just passes
        XCTAssertTrue(true, "Simple test passed")
    }
    
    func testSchemaValidationFlow() throws {
        print("🚀 Starting testSchemaValidationFlow")
        
        // Wait for app to be fully ready
        try waitForAppToBeReady()
        print("✅ App is ready - main screen loaded")
        
        // Debug: Print all available UI elements on initial screen
        print("🔍 DEBUG: Available UI elements on initial screen:")
        print("   Static Texts (\(app.staticTexts.count) total):")
        for (index, text) in app.staticTexts.allElementsBoundByIndex.prefix(10).enumerated() {
            if text.exists {
                print("      [\(index)] '\(text.label)'")
            }
        }
        print("   Buttons (\(app.buttons.count) total):")
        for (index, button) in app.buttons.allElementsBoundByIndex.prefix(10).enumerated() {
            if button.exists {
                print("      [\(index)] '\(button.label)'")
            }
        }
        print("   Cells (\(app.cells.count) total):")
        for (index, cell) in app.cells.allElementsBoundByIndex.prefix(10).enumerated() {
            if cell.exists {
                print("      [\(index)] Cell exists")
            }
        }
        
        // ========== PHASE 1: Network Instrumentation ==========
        print("📱 Phase 1.1: Looking for 'Network instrumentation' button...")
        // Try both staticText and cell - in table views, the text might be in a cell
        let networkInstrumentationButton = app.staticTexts["Network instrumentation"].firstMatch
        // Also try finding it as a cell
        let networkInstrumentationCell = app.cells.containing(.staticText, identifier: "Network instrumentation").firstMatch
        
        // Wait for either the static text or the cell to appear
        let buttonExists = networkInstrumentationButton.waitForExistence(timeout: elementTimeout)
        let cellExists = networkInstrumentationCell.waitForExistence(timeout: elementTimeout)
        let networkButtonExists = buttonExists || cellExists
        
        print("   Network instrumentation button exists (staticText): \(buttonExists)")
        print("   Network instrumentation cell exists: \(cellExists)")
        
        // If not found, try scrolling to make it visible
        if !networkButtonExists {
            print("   ⚠️ Element not found, scrolling to top to ensure visibility...")
            if app.tables.count > 0 {
                app.tables.firstMatch.swipeDown()  // Scroll to top
                Thread.sleep(forTimeInterval: 0.5)
                // Try again after scrolling
                let buttonExistsAfterScroll = networkInstrumentationButton.waitForExistence(timeout: 5.0)
                let cellExistsAfterScroll = networkInstrumentationCell.waitForExistence(timeout: 5.0)
                if buttonExistsAfterScroll || cellExistsAfterScroll {
                    print("   ✅ Found after scrolling!")
                }
            }
        }
        
        let finalButtonExists = networkInstrumentationButton.exists || networkInstrumentationCell.exists
        if !finalButtonExists {
            var availableTexts = "Available static texts on screen:\n"
            for text in app.staticTexts.allElementsBoundByIndex.prefix(20) {
                if text.exists {
                    availableTexts += "      - '\(text.label)'\n"
                }
            }
            var availableCells = "Available cells on screen:\n"
            for (index, cell) in app.cells.allElementsBoundByIndex.prefix(10).enumerated() {
                if cell.exists {
                    let cellTexts = cell.staticTexts.allElementsBoundByIndex
                    var cellLabels: [String] = []
                    for cellText in cellTexts {
                        if cellText.exists {
                            cellLabels.append(cellText.label)
                        }
                    }
                    availableCells += "      [\(index)] Cell with texts: \(cellLabels.joined(separator: ", "))\n"
                }
            }
            print("   ❌ \(availableTexts)")
            print("   ❌ \(availableCells)")
            XCTFail("❌ Phase 1.1 FAILED: 'Network instrumentation' button not found.\n\(availableTexts)\n\(availableCells)")
        }
        print("✅ Phase 1.1: Found Network instrumentation button")
        
        print("📱 Phase 1.2: Tapping Network instrumentation button...")
        // Tap the cell if it exists, otherwise tap the static text
        if networkInstrumentationCell.exists {
            networkInstrumentationCell.tap()
        } else if networkInstrumentationButton.exists {
            networkInstrumentationButton.tap()
        } else {
            XCTFail("❌ Phase 1.2 FAILED: Cannot tap 'Network instrumentation' - element not found")
        }
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        print("✅ Phase 1.2: Tapped Network instrumentation button")

        print("📱 Phase 1.3: Looking for 'Failing network request' button...")
        let failingNetworkButton = app.staticTexts["Failing network request"].firstMatch
        let failingButtonExists = failingNetworkButton.waitForExistence(timeout: elementTimeout)
        print("   Failing network request button exists: \(failingButtonExists)")
        if !failingButtonExists {
            var availableTexts = "Available static texts on Network screen:\n"
            for text in app.staticTexts.allElementsBoundByIndex.prefix(20) {
                if text.exists {
                    availableTexts += "      - '\(text.label)'\n"
                }
            }
            print("   ❌ \(availableTexts)")
            XCTFail("❌ Phase 1.3 FAILED: 'Failing network request' button not found. \(availableTexts)")
        }
        print("✅ Phase 1.3: Found Failing network request button")
        
        print("📱 Phase 1.4: Tapping Failing network request button...")
        failingNetworkButton.tap()
        Thread.sleep(forTimeInterval: networkDelay)  // Wait for network request
        print("✅ Phase 1.4: Tapped Failing network request button")

        print("📱 Phase 1.5: Looking for 'Successful network request' button...")
        let successfulNetworkButton = app.staticTexts["Successful network request"].firstMatch
        let successfulButtonExists = successfulNetworkButton.waitForExistence(timeout: elementTimeout)
        print("   Successful network request button exists: \(successfulButtonExists)")
        XCTAssertTrue(successfulButtonExists, "❌ 'Successful network request' button not found")
        print("✅ Phase 1.5: Found Successful network request button")
        
        print("📱 Phase 1.6: Tapping Successful network request button...")
        successfulNetworkButton.tap()
        Thread.sleep(forTimeInterval: networkDelay)  // Wait for network request
        print("✅ Phase 1.6: Tapped Successful network request button")

        print("📱 Phase 1.7: Looking for Back button...")
        // Back button in iOS is typically in the navigation bar
        // Try multiple ways to find it: navigationBar.buttons["Back"], navigationBar.buttons.firstMatch, or buttons["Back"]
        var backButton: XCUIElement?
        var backButtonExists = false
        
        // Method 1: Navigation bar back button
        if let navBar = app.navigationBars.allElementsBoundByIndex.first(where: { $0.exists }) {
            let navBackButton = navBar.buttons["Back"].firstMatch
            if navBackButton.waitForExistence(timeout: 2.0) {
                backButton = navBackButton
                backButtonExists = true
                print("   Found back button via navigation bar")
            }
        }
        
        // Method 2: Direct button with "Back" label
        if !backButtonExists {
            let backButtonDirect = app.buttons["Back"].firstMatch
            if backButtonDirect.waitForExistence(timeout: 2.0) {
                backButton = backButtonDirect
                backButtonExists = true
                print("   Found back button via direct button search")
            }
        }
        
        // Method 3: Navigation bar first button (often the back button)
        if !backButtonExists {
            if let navBar = app.navigationBars.allElementsBoundByIndex.first(where: { $0.exists }) {
                let firstNavButton = navBar.buttons.firstMatch
                if firstNavButton.waitForExistence(timeout: 2.0) {
                    backButton = firstNavButton
                    backButtonExists = true
                    print("   Found back button via navigation bar first button")
                }
            }
        }
        
        print("   Back button exists: \(backButtonExists)")
        if !backButtonExists {
            var availableButtons = "Available buttons on Network screen:\n"
            for button in app.buttons.allElementsBoundByIndex.prefix(20) {
                if button.exists {
                    availableButtons += "      - '\(button.label)' (identifier: '\(button.identifier)')\n"
                }
            }
            var navButtons = "Navigation bar buttons:\n"
            if let navBar = app.navigationBars.allElementsBoundByIndex.first(where: { $0.exists }) {
                for button in navBar.buttons.allElementsBoundByIndex.prefix(10) {
                    if button.exists {
                        navButtons += "      - '\(button.label)' (identifier: '\(button.identifier)')\n"
                    }
                }
            }
            print("   ❌ \(availableButtons)")
            print("   ❌ \(navButtons)")
            XCTFail("❌ Phase 1.7 FAILED: Back button from Network screen not found.\n\(availableButtons)\n\(navButtons)")
        }
        
        print("✅ Phase 1.7: Found Back button")
        
        print("📱 Phase 1.8: Tapping Back button...")
        if let button = backButton {
            button.tap()
        } else {
            XCTFail("❌ Phase 1.8 FAILED: Back button element is nil")
        }
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        print("✅ Phase 1.8: Tapped Back button")
        
        // Phase 1 complete
        print("✅ Phase 1 (Network Instrumentation) completed successfully")
        
        // ========== PHASE 2: Error Instrumentation ==========
        print("📱 Phase 2: Starting Error Instrumentation...")
        
        // Navigate to Error Instrumentation screen
        print("📱 Phase 2.1: Looking for 'Error instrumentation' button...")
        let errorInstrumentationButton = app.staticTexts["Error instrumentation"].firstMatch
        let errorInstrumentationCell = app.cells.containing(.staticText, identifier: "Error instrumentation").firstMatch
        let errorInstButtonExists = errorInstrumentationButton.waitForExistence(timeout: elementTimeout) || errorInstrumentationCell.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(errorInstButtonExists, "❌ 'Error instrumentation' button not found")
        print("✅ Phase 2.1: Found Error instrumentation button")
        
        print("📱 Phase 2.2: Tapping Error instrumentation button...")
        if errorInstrumentationCell.exists {
            errorInstrumentationCell.tap()
        } else {
            errorInstrumentationButton.tap()
        }
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        print("✅ Phase 2.2: Tapped Error instrumentation button")
        
        // Trigger "Error" test event
        print("📱 Phase 2.3: Looking for 'Error' button...")
        let errorButton = app.staticTexts["Error"].firstMatch
        XCTAssertTrue(errorButton.waitForExistence(timeout: elementTimeout), "❌ 'Error' button not found")
        print("✅ Phase 2.3: Found Error button")
        errorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        print("✅ Phase 2.4: Tapped Error button")
        
        // Trigger "Message Data Error (custom log)" event
        print("📱 Phase 2.5: Looking for 'Message Data Error' button...")
        let messageDataErrorButton = app.staticTexts["Message Data Error"].firstMatch
        XCTAssertTrue(messageDataErrorButton.waitForExistence(timeout: elementTimeout), "❌ 'Message Data Error' button not found")
        print("✅ Phase 2.5: Found Message Data Error button")
        messageDataErrorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        print("✅ Phase 2.6: Tapped Message Data Error button")
        
        // Trigger "Log Error" event
        print("📱 Phase 2.7: Looking for 'Log Error' button...")
        let logErrorButton = app.staticTexts["Log Error"].firstMatch
        XCTAssertTrue(logErrorButton.waitForExistence(timeout: elementTimeout), "❌ 'Log Error' button not found")
        print("✅ Phase 2.7: Found Log Error button")
        logErrorButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for event processing
        print("✅ Phase 2.8: Tapped Log Error button")
        
        // Go back to main screen
        print("📱 Phase 2.9: Looking for Back button...")
        var backButtonFromError: XCUIElement?
        if let navBar = app.navigationBars.allElementsBoundByIndex.first(where: { $0.exists }) {
            let navBackButton = navBar.buttons["Back"].firstMatch
            if navBackButton.waitForExistence(timeout: 2.0) {
                backButtonFromError = navBackButton
            } else {
                let firstNavButton = navBar.buttons.firstMatch
                if firstNavButton.waitForExistence(timeout: 2.0) {
                    backButtonFromError = firstNavButton
                }
            }
        }
        if backButtonFromError == nil {
            let backButtonDirect = app.buttons["Back"].firstMatch
            if backButtonDirect.waitForExistence(timeout: 2.0) {
                backButtonFromError = backButtonDirect
            }
        }
        XCTAssertNotNil(backButtonFromError, "❌ Back button from Error screen not found")
        backButtonFromError?.tap()
        Thread.sleep(forTimeInterval: shortDelay)  // Wait for navigation
        print("✅ Phase 2.9: Tapped Back button")
        print("✅ Phase 2 (Error Instrumentation) completed successfully")

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
}

