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
    
    func testStartColdStartMonitoring() {
        metricsManager.startColdStartMonitoring()
        XCTAssertNotNil(metricsManager.launchStartTime, "Cold start monitoring should set launchStartTime")
    }
    
    func testAppWillEnterForeground() {
        // Set up foreground start time to simulate entering the background
        metricsManager.foregroundStartTime = CFAbsoluteTimeGetCurrent() - 1.0  // Simulate 1 second ago
        metricsManager.appDidEnterBackgroundNotification()
        
        // Simulate entering foreground
        metricsManager.appWillEnterForegroundNotification()
        metricsManager.appDidBecomeActiveNotification()
        // Check if foregroundEndTime is set and warm start duration is calculated
        XCTAssertNotNil(metricsManager.foregroundEndTime, "Foreground end time should be set after entering foreground")
        XCTAssertTrue(metricsManager.foregroundEndTime! - metricsManager.foregroundStartTime! >= 0.0, "Warm start duration should be calculated")
    }
    
    func testAppDidEnterBackgroundNotification() {
        
        metricsManager.fpsTrigger = mockFPSMonitor
        // Simulate the method being called when the app enters background
        metricsManager.appDidEnterBackgroundNotification()
        
        // Verify that the FPS monitoring was stopped
        XCTAssertTrue(mockFPSMonitor.stopMonitoringCalled, "stopMonitoring() should be called when app enters background")
        
        // Verify that warmMetricIsActive is set to true
        XCTAssertTrue(metricsManager.warmMetricIsActive, "warmMetricIsActive should be set to true when app enters background")
    }
    
    func testHandleNotificationForColdStart() {
        // Simulate the cold start by setting the start time
        metricsManager.launchStartTime = CFAbsoluteTimeGetCurrent() - 2.0  // Simulate 2 seconds ago
        
        // Prepare a notification with the coldEnd metric
        let notification = Notification(name: .cxRumNotificationMetrics, object: [CXMobileVitalsType.cold.rawValue: CFAbsoluteTimeGetCurrent()])
        
        // Handle the notification
        metricsManager.handleNotification(notification: notification)
        
        // Verify that the cold start duration is calculated correctly
        XCTAssertNotNil(metricsManager.launchEndTime, "Launch end time should be set after cold start handling")
        XCTAssertEqual(metricsManager.launchEndTime! - metricsManager.launchStartTime!, 2.0, accuracy: 0.1, "Cold start duration should be approximately 2 seconds")
    }
    
    func testStartANRMonitoring() {
        metricsManager.startANRMonitoring()
        XCTAssertNotNil(metricsManager.anrDetector, "ANR monitoring should start and anrDetector should be initialized")
    }
    
    func testFPSSamplingMonitoringStartAndStop() {
        // Simulate starting FPS sampling monitoring
        metricsManager.startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: 30)
        
        // FPS monitoring should be running
        XCTAssertTrue(metricsManager.fpsTrigger.isRunning, "FPS sampling should be running after calling startFPSSamplingMonitoring")
        
        // Stop FPS monitoring
        metricsManager.appDidEnterBackgroundNotification()
        
        // FPS monitoring should stop
        XCTAssertFalse(metricsManager.fpsTrigger.isRunning, "FPS sampling should stop when app enters background")
    }
    
    func testWarmStartVital() {
        self.metricsManager.launchStartTime = nil
        let warmTimestamp: Double = 1234567890.0
        
        let params: [String: Any] = [
            CXMobileVitalsType.warm.rawValue: warmTimestamp
        ]
        
        let result = metricsManager.getCXMobileVitals(params: params)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .warm)
        XCTAssertEqual(result?.value, "\(Int(warmTimestamp))")
    }
    
    func testColdStartVital() {
        let startTime: CFAbsoluteTime = 1000.0
        let endTime: CFAbsoluteTime = 1001.234  // duration: 1.234 seconds
        
        self.metricsManager.launchStartTime = startTime
        
        let params: [String: Any] = [
            CXMobileVitalsType.cold.rawValue: endTime
        ]
        
        let result = metricsManager.getCXMobileVitals(params: params)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .cold)
        
        let expectedMilliseconds = Int((endTime - startTime) * 1000)
        XCTAssertEqual(result?.value, "\(expectedMilliseconds)")
    }
    
    func testNoMatchingVitals() {
        self.metricsManager.launchStartTime = nil

        let params: [String: Any] = [
            "nonMatchingKey": 123
        ]
        
        let result = self.metricsManager.getCXMobileVitals(params: params)
        
        XCTAssertNil(result)
    }
}

// Mock class to simulate the behavior of fpsTrigger
class MockFPSTrigger: FPSTrigger {
    var stopMonitoringCalled = false
    
    override func stopMonitoring() {
        stopMonitoringCalled = true
    }
}
