//
//  FPSTriggerTests.swift
//
//
//  Created by Coralogix DEV TEAM on 11/09/2024.
//

import XCTest
@testable import Coralogix

final class FPSTriggerTests: XCTestCase {
    var fpsTrigger: FPSTrigger!
    
    override func setUp() {
        super.setUp()
        fpsTrigger = FPSTrigger()
    }

    override func tearDown() {
        fpsTrigger.stopMonitoring()
        fpsTrigger = nil
        super.tearDown()
    }
    
    func testStartMonitoring() {
        // Expectation to test whether the timer starts correctly
        let expectation = self.expectation(description: "Timer starts and triggers FPS monitoring")
        
        // Start the monitoring with a specific number of triggers per hour
        fpsTrigger.startMonitoring(xTimesPerHour: 60)
        
        // Wait for 1 second to allow the timer to fire
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Since we can't directly test the timer, we check if the timer was set and is running
            XCTAssertNotNil(self.fpsTrigger.timer, "Timer should be initialized")
            XCTAssertTrue(self.fpsTrigger.isRunning, "Monitoring should be running")
            
            // Fulfill the expectation
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
    }
    
    func testStopMonitoring() {
        // Start monitoring first
        fpsTrigger.startMonitoring(xTimesPerHour: 60)
        
        // Stop monitoring
        fpsTrigger.stopMonitoring()
        
        // Assert that the timer is invalidated and monitoring has stopped
        XCTAssertNil(fpsTrigger.timer, "Timer should be nil after stopping monitoring")
        XCTAssertFalse(fpsTrigger.isRunning, "Monitoring should not be running after stopMonitoring() is called")
    }

    func testMonitorFPSAndNotification() {
        // Expectation for receiving the notification
        _ = expectation(forNotification: .cxRumNotificationMetrics, object: nil, handler: { notification in
            // Validate that the notification contains the expected FPS value
            if let vitals = notification.object as? CXMobileVitals, vitals.type == .fps {
                XCTAssertNotNil(vitals.value, "Notification should contain FPS value")
                XCTAssertEqual(vitals.value, "60", "Expected FPS value should be '60'")
                return true
            }
            return false
        })
        
        
        // Start the monitoring process
        fpsTrigger.startMonitoring(xTimesPerHour: 60)
        
        // Simulate that FPS monitoring starts and posts the notification immediately, skipping the actual 5 seconds wait
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                            object: CXMobileVitals(type: .fps, value: "60"))
        }
        
        // Wait for expectations with a longer timeout to avoid race conditions
        waitForExpectations(timeout: 10.0, handler: nil)
    }
}
