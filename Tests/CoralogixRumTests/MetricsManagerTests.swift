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
}

// Mock class to simulate the behavior of fpsTrigger
class MockFPSTrigger: FPSTrigger {
    var stopMonitoringCalled = false
    
    override func stopMonitoring() {
        stopMonitoringCalled = true
    }
}
