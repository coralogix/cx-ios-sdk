//
//  ANRDetectorTests.swift
//
//
//  Created by Coralogix DEV TEAM on 08/09/2024.
//

import XCTest
import Foundation
@testable import Coralogix

final class ANRDetectorTests: XCTestCase {
    
    private var anrDetector: ANRDetector!
    private var expectation: XCTestExpectation!
    
    override func setUp() {
        super.setUp()
        // Initialize ANRDetector with short intervals for faster testing
        anrDetector = ANRDetector(checkInterval: 0.1, maxBlockTime: 0.5)
        // Set a default ANR handler closure that does nothing, we'll override it in specific tests
        anrDetector.handleANRClosure = { }
    }
    
    override func tearDown() {
        anrDetector.stopMonitoring()
        anrDetector = nil
        expectation = nil
        super.tearDown()
    }
    
    func testInitialization() {
        XCTAssertNotNil(anrDetector, "ANRDetector should be initialized")
        XCTAssertEqual(anrDetector.checkInterval, 0.1, "Check interval should be set correctly")
        XCTAssertEqual(anrDetector.maxBlockTime, 0.5, "Max block time should be set correctly")
    }
    
    func testStartMonitoring() {
        anrDetector.startMonitoring()
        XCTAssertNotNil(anrDetector.timer, "Timer should be scheduled after startMonitoring")
        XCTAssertTrue(anrDetector.timer!.isValid, "Timer should be valid after startMonitoring")
    }
    
    func testStopMonitoring() {
        anrDetector.startMonitoring()
        anrDetector.stopMonitoring()
        XCTAssertNil(anrDetector.timer, "Timer should be nil after stopMonitoring")
        // Note: It's harder to directly assert timer invalidation without internal access,
        // but checking for nil is a good proxy.
    }
    
    func testANRIsDetectedWhenMainThreadIsBlocked() {
        // Create an expectation for the ANR handler to be called
        expectation = XCTestExpectation(description: "ANR handler should be called")
        
        // Override the ANR handler to fulfill the expectation
        anrDetector.handleANRClosure = {
            self.expectation.fulfill()
        }
        
        // Start monitoring
        anrDetector.startMonitoring()
        
        // Simulate blocking the main thread for longer than maxBlockTime
        let blockDuration = anrDetector.maxBlockTime + 0.2 // Slightly longer than maxBlockTime
        DispatchQueue.main.async {
            Thread.sleep(forTimeInterval: blockDuration)
        }
        
        // Wait for the ANR handler to be called
        wait(for: [expectation], timeout: blockDuration + 1.0) // Add buffer for execution
    }
    
    func testANRIsNotDetectedWhenMainThreadIsResponsive() {
        // Create an expectation for the ANR handler *not* to be called
        expectation = XCTestExpectation(description: "ANR handler should not be called")
        expectation.isInverted = true // This expectation will pass if not fulfilled
        
        // Override the ANR handler to fail the test if it's called
        anrDetector.handleANRClosure = {
            XCTFail("ANR handler should not be called when the main thread is responsive")
            self.expectation.fulfill() // Fulfill to make sure the wait doesn't time out
        }
        
        // Start monitoring
        anrDetector.startMonitoring()
        
        // Simulate activity on the main thread that keeps it responsive
        let checkInterval = anrDetector.checkInterval
        let numberOfChecks = 5 // Simulate a few checks
        for _ in 0..<numberOfChecks {
            DispatchQueue.main.async {
                // Do a small operation on the main thread
                let _ = 1 + 1
            }
            Thread.sleep(forTimeInterval: checkInterval / 2) // Sleep less than checkInterval
        }
        
        // Wait for a short period to ensure no ANR is triggered
        wait(for: [expectation], timeout: anrDetector.maxBlockTime + 1.0)
    }
    
    func testANRIsDetectedAfterExtendedBlock() {
        // This test ensures that if the main thread is blocked for a duration
        // that spans multiple check intervals, the ANR is still detected.
        
        expectation = XCTestExpectation(description: "ANR handler should be called after extended block")
        
        anrDetector.handleANRClosure = {
            self.expectation.fulfill()
        }
        
        anrDetector.startMonitoring()
        
        // Block the main thread for a duration significantly longer than maxBlockTime
        // and also longer than a few check intervals.
        let extendedBlockDuration = anrDetector.maxBlockTime * 3 // e.g., 1.5 seconds if maxBlockTime is 0.5s
        DispatchQueue.main.async {
            Thread.sleep(forTimeInterval: extendedBlockDuration)
        }
        
        wait(for: [expectation], timeout: extendedBlockDuration + 1.0)
    }
    
    func testHandleANRCallsClosureAndLogs() {
        // This test focuses on the `handleANR` method itself,
        // not necessarily triggered by the timer mechanism, but by directly calling it.
        
        expectation = XCTestExpectation(description: "ANR handler closure should be called")
        
        anrDetector.handleANRClosure = {
            self.expectation.fulfill()
        }
       
        anrDetector.handleANR()
        
        wait(for: [expectation], timeout: 1.0) // Short timeout as it's a direct call
    }
}
