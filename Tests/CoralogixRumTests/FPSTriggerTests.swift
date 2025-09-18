//
//  FPSTriggerTests.swift
//
//
//  Created by Coralogix DEV TEAM on 11/09/2024.
//

import XCTest
@testable import Coralogix

final class FPSTriggerTests: XCTestCase {
    var fpsDetector: FPSDetector!
    
    override func setUp() {
        super.setUp()
        fpsDetector = FPSDetector()
    }

    override func tearDown() {
        fpsDetector.stopMonitoring()
        fpsDetector = nil
        super.tearDown()
    }
    
    func testStartMonitoring() {
        // Expectation to test whether the timer starts correctly
        let expectation = self.expectation(description: "Timer starts and triggers FPS monitoring")
        
        // Start the monitoring with a specific number of triggers per hour
        fpsDetector.startMonitoring()
        
        // Wait for 1 second to allow the timer to fire
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Since we can't directly test the timer, we check if the timer was set and is running
            XCTAssertNotNil(self.fpsDetector.timer, "Timer should be initialized")
            XCTAssertTrue(self.fpsDetector.isRunning, "Monitoring should be running")
            
            // Fulfill the expectation
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
    }
    
    func testStopMonitoring() {
        // Start monitoring first
        fpsDetector.startMonitoring()
        
        // Stop monitoring
        fpsDetector.stopMonitoring()
        
        // Assert that the timer is invalidated and monitoring has stopped
        XCTAssertNil(fpsDetector.timer, "Timer should be nil after stopping monitoring")
        XCTAssertFalse(fpsDetector.isRunning, "Monitoring should not be running after stopMonitoring() is called")
    }
}
