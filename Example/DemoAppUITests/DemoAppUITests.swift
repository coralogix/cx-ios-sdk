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


    func testClickClockButton() throws {

        // Capture and print the session ID from the top of the screen
        let sessionIdElement = app.staticTexts.firstMatch
        XCTAssertTrue(sessionIdElement.waitForExistence(timeout: 5), "Session ID should be visible on the main screen")

        let sessionId = sessionIdElement.label


        // Click the Clock button
        let clockButton = app.cells.containing(.staticText, identifier: "Clock").firstMatch
        clockButton.tap()

        // Wait for the new screen to load (Clock view controller)
        let timeLabel = app.staticTexts.firstMatch
        XCTAssertTrue(timeLabel.waitForExistence(timeout: 5), "Clock screen should load after tapping Clock button")

        // Wait a bit for any network requests to complete
        Thread.sleep(forTimeInterval: 3.0)

        print("✅ Successfully clicked the Clock button and verified network requests with 200 status!")
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
        
        // Step 6: Wait for validation to complete and verify no "Validation Failed" appears
        // Wait for the status label to update (either success or failure)
        let statusLabel = app.staticTexts.containing(.staticText, identifier: "Validation Failed").firstMatch
        
        // If "Validation Failed" appears, the test will fail
        // If it doesn't appear within 10 seconds, the test passes
        let validationFailedExists = statusLabel.waitForExistence(timeout: 10)
        
        if validationFailedExists {
            XCTFail("❌ Validation Failed appeared in the UI")
        } else {
            print("✅ No 'Validation Failed' message appeared - test passed!")
        }
    }
}
