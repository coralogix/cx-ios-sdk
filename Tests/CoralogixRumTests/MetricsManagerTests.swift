//
//  MetricsManagerTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 11/09/2024.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class MetricsManagerTests: XCTestCase {
    
    var metricsManager: MetricsManager!
    var mockFPSMonitor: MockFPSTrigger!

    override func setUp() {
        super.setUp()
        self.metricsManager = MetricsManager()
        self.mockFPSMonitor = MockFPSTrigger()
    }

    override func tearDown() {
        mockFPSMonitor = nil
        super.tearDown()
    }
    
    func testStartANRMonitoring() {
        metricsManager.startANRMonitoring()
        XCTAssertNotNil(metricsManager.anrDetector, "ANR monitoring should start and anrDetector should be initialized")
    }
    
    func testANRErrorClosureIsCalled() {
        let expectation = XCTestExpectation(description: "ANR error closure should be called")
        var receivedErrorMessage: String?
        var receivedErrorType: String?
        
        // Set up the ANR error closure
        metricsManager.anrErrorClosure = { errorMessage, errorType in
            receivedErrorMessage = errorMessage
            receivedErrorType = errorType
            expectation.fulfill()
        }
        
        // Start monitoring
        metricsManager.startANRMonitoring()
        
        // Simulate ANR detection by directly calling the detector's handleANR
        metricsManager.anrDetector?.handleANR()
        
        wait(for: [expectation], timeout: 1.0)
        
        // Verify the error message and type
        XCTAssertNotNil(receivedErrorMessage, "Error message should be received")
        XCTAssertNotNil(receivedErrorType, "Error type should be received")
        XCTAssertEqual(receivedErrorType, "ANR", "Error type should be 'ANR'")
        XCTAssertEqual(receivedErrorMessage, "Application Not Responding", "Error message should be 'Application Not Responding'")
    }
    
    func testANRDoesNotCallMobileVitalsClosure() {
        let expectation = XCTestExpectation(description: "Mobile vitals closure should NOT be called for ANR")
        expectation.isInverted = true
        
        // Set up the mobile vitals closure (should NOT be called)
        metricsManager.metricsManagerClosure = { _ in
            XCTFail("Mobile vitals closure should not be called for ANR events")
            expectation.fulfill()
        }
        
        // Set up the ANR error closure (should be called)
        metricsManager.anrErrorClosure = { _, _ in
            // ANR error closure called correctly
        }
        
        // Start monitoring
        metricsManager.startANRMonitoring()
        
        // Simulate ANR detection
        metricsManager.anrDetector?.handleANR()
        
        wait(for: [expectation], timeout: 1.0)
    }
}

// Mock class to simulate the behavior of fpsDetector
class MockFPSTrigger: FPSDetector {
    var stopMonitoringCalled = false
    
    override func stopMonitoring() {
        stopMonitoringCalled = true
    }
}
