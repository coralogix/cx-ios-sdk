//
//  CXANRDetectorTests.swift
//
//
//  Created by Coralogix DEV TEAM on 08/09/2024.
//

import XCTest
@testable import Coralogix

final class CXANRDetectorTests: XCTestCase {
    
    var anrDetector: CXANRDetector!
    var anrDetected = false
    
    override func setUp() {
        super.setUp()
        // Initialize with a short maxBlockTime for faster tests
        anrDetector = CXANRDetector(checkInterval: 0.1, maxBlockTime: 0.2)
        
        // Override the handleANR with a closure to test ANR detection
        anrDetector.handleANRClosure = { [weak self] in
            self?.anrDetected = true
        }
    }
    
    override func tearDown() {
        anrDetector.stopMonitoring()
        anrDetector = nil
        anrDetected = false
        super.tearDown()
    }
    
    func testStartMonitoringStartsTimer() {
        // Ensure the timer is started
        anrDetector.startMonitoring()
        XCTAssertNotNil(anrDetector.timer, "Timer should be started when startMonitoring is called")
    }
    
    func testStopMonitoringStopsTimer() {
        // Ensure the timer is stopped
        anrDetector.startMonitoring()
        anrDetector.stopMonitoring()
        XCTAssertNil(anrDetector.timer, "Timer should be nil after stopMonitoring is called")
    }
    
    func testANRDetection() {
        // Start monitoring
        anrDetector.startMonitoring()

        // Wait for the ANR detection to occur
        let expectation = self.expectation(description: "ANR should be detected")

        // Block the main thread for more than maxBlockTime (0.2 seconds) to simulate ANR
        DispatchQueue.main.async {
            let blockStartTime = CFAbsoluteTimeGetCurrent()
            while CFAbsoluteTimeGetCurrent() - blockStartTime < 0.3 {
                // Blocking the main thread for 0.3 seconds to simulate ANR
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // At this point, the main thread should have been blocked long enough to trigger ANR
            XCTAssertTrue(self?.anrDetected ?? false, "ANR should have been detected after the main thread becomes unresponsive")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    
    func testNoANRDetectionWhenMainThreadResponsive() {
        // Ensure that ANR is not detected if the main thread is responsive
        anrDetector.startMonitoring()
        
        // Wait for 0.1 seconds (less than maxBlockTime)
        let expectation = self.expectation(description: "ANR should not be detected")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            XCTAssertFalse(self?.anrDetected ?? false, "ANR should not have been detected when the main thread is responsive")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

