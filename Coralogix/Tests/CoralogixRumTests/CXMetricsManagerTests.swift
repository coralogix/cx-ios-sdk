//
//  CXMetricsManagerTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 11/09/2024.
//

import XCTest
@testable import Coralogix

final class CXMetricsManagerTests: XCTestCase {
    
    var metricsManager: CXMetricsManager!

    override func setUp() {
        super.setUp()
        self.metricsManager = CXMetricsManager()
    }

    override func tearDown() {
        NotificationCenter.default.removeObserver(metricsManager as Any)
        metricsManager = nil
        super.tearDown()
    }
    
    func testStartColdStartMonitoring() {
        metricsManager.startColdStartMonitoring()
        XCTAssertNotNil(metricsManager.launchStartTime, "Cold start monitoring should set launchStartTime")
    }
    
    func testAppWillEnterForeground() {
        // Set up foreground start time to simulate entering the background
        metricsManager.foregroundStartTime = CFAbsoluteTimeGetCurrent() - 1.0  // Simulate 1 second ago
        
        // Simulate entering foreground
        metricsManager.appWillEnterForeground()
        
        // Check if foregroundEndTime is set and warm start duration is calculated
        XCTAssertNotNil(metricsManager.foregroundEndTime, "Foreground end time should be set after entering foreground")
        XCTAssertTrue(metricsManager.foregroundEndTime! - metricsManager.foregroundStartTime! >= 1.0, "Warm start duration should be calculated")
    }
    
    func testApplicationDidEnterBackground() {
        metricsManager.applicationDidEnterBackground()
        XCTAssertNotNil(metricsManager.foregroundStartTime, "Foreground start time should be set when app enters background")
        XCTAssertNil(metricsManager.foregroundEndTime, "Foreground end time should be nil when app enters background")
    }
    
    func testAppWillTerminateNotification() {
        // Simulate setting up ANR detector
        metricsManager.cxAnrDetector = CXANRDetector()
        
        // Call the termination handler
        metricsManager.appWillTerminateNotification()
        
        // Ensure ANR monitoring is stopped
        XCTAssertNil(metricsManager.cxAnrDetector, "ANR monitoring should stop on app termination")
    }
    
    func testHandleNotificationForColdStart() {
        // Simulate the cold start by setting the start time
        metricsManager.launchStartTime = CFAbsoluteTimeGetCurrent() - 2.0  // Simulate 2 seconds ago
        
        // Prepare a notification with the coldEnd metric
        let notification = Notification(name: .cxRumNotificationMetrics, object: [Keys.coldEnd.rawValue: CFAbsoluteTimeGetCurrent()])
        
        // Handle the notification
        metricsManager.handleNotification(notification: notification)
        
        // Verify that the cold start duration is calculated correctly
        XCTAssertNotNil(metricsManager.launchEndTime, "Launch end time should be set after cold start handling")
        XCTAssertEqual(metricsManager.launchEndTime! - metricsManager.launchStartTime!, 2.0, accuracy: 0.1, "Cold start duration should be approximately 2 seconds")
    }
    
    func testStartANRMonitoring() {
        metricsManager.startANRMonitoring()
        XCTAssertNotNil(metricsManager.cxAnrDetector, "ANR monitoring should start and cxAnrDetector should be initialized")
    }
    
    func testFPSSamplingMonitoringStartAndStop() {
        // Simulate starting FPS sampling monitoring
        metricsManager.startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: 30)
        
        // FPS monitoring should be running
        XCTAssertTrue(metricsManager.cxFPSTrigger.isRunning, "FPS sampling should be running after calling startFPSSamplingMonitoring")
        
        // Stop FPS monitoring
        metricsManager.applicationDidEnterBackground()
        
        // FPS monitoring should stop
        XCTAssertFalse(metricsManager.cxFPSTrigger.isRunning, "FPS sampling should stop when app enters background")
    }
}
