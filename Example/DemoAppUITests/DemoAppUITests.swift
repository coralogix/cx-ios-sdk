//
//  DemoAppUITests.swift
//  DemoAppUITests
//
//  Created by UI Test on 2024.
//

import XCTest


final class DemoAppUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        
        // Initialize the app
        app = XCUIApplication()
        app.launch()
    }
    
    func testSchemaValidationFlow() throws {
        // Step 1: Click "Clock" button
        let clockButton = app.cells.containing(.staticText, identifier: "Clock").firstMatch
        XCTAssertTrue(clockButton.waitForExistence(timeout: 5), "Clock button should be visible")
        clockButton.tap()
        
        // Wait for Clock screen to load
        let timeLabel = app.staticTexts.firstMatch
        XCTAssertTrue(timeLabel.waitForExistence(timeout: 5), "Clock screen should load")
        
        // Step 2: Return back to main screen
        app.navigationBars.buttons.element(boundBy: 0).tap() // Back button
        
        // Step 3: Click "Verify schema" button
        let verifySchemaButton = app.cells.containing(.staticText, identifier: "Verify schema").firstMatch
        XCTAssertTrue(verifySchemaButton.waitForExistence(timeout: 5), "Verify schema button should be visible")
        verifySchemaButton.tap()
        
        // Wait for Schema Validation screen to load
        let validateSchemaButton = app.buttons["Validate Schema"]
        XCTAssertTrue(validateSchemaButton.waitForExistence(timeout: 5), "Validate Schema button should be visible")
        
        // Step 4: Wait 2 seconds
        Thread.sleep(forTimeInterval: 2.0)
        
        // Step 5: Click "Validate Schema" button
        validateSchemaButton.tap()
        
        let timeout: TimeInterval = 5.0
        RunLoop.current.run(until: Date().addingTimeInterval(timeout))
        // Step 6: Wait for validation to complete and verify no "Validation Failed" appears
        let allStaticTexts = app.staticTexts.allElementsBoundByIndex

        for label in allStaticTexts {
            print("Label text: \(label.label)")
            let labelText = label.label
            if labelText.contains("Validation Failed") {
                XCTFail("❌ Validation Failed appeared in the UI")
            }
        }
        print("✅ No 'Validation Failed' message appeared - test passed!")
    }
}
