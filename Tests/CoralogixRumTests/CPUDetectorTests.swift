//
//  CPUDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 13/08/2025.
//
import XCTest
@testable import Coralogix

final class CPUDetectorTests: XCTestCase {
    var cpuDetector: CPUDetector!
    var cpuDetected = false
    
    override func setUp() {
        super.setUp()
        // Initialize with a short maxBlockTime for faster tests
        cpuDetector = CPUDetector(checkInterval: 0.1)
        
        // Override the handleANR with a closure to test ANR detection
        cpuDetector.handleCpuClosure = { [weak self] in
            self?.cpuDetected = true
        }
    }
    
    override func tearDown() {
        cpuDetector.stopMonitoring()
        cpuDetector = nil
        cpuDetected = false
        super.tearDown()
    }
    
    func testEmitsThreeMetricsForSingleTick() {
        // Expect to receive exactly 3 metrics in one sampling round:
        // .cpuUsagePercent, .totalCpuTimeMs, .mainThreadCpuTimeMs sharing the same uuid
        let expect = expectation(description: "Received three CPU metrics (same UUID)")
        expect.expectedFulfillmentCount = 1
        
        // Storage for first observed tick, keyed by uuid
        var firstTickUUID: String?
        var receivedTypes = Set<CXMobileVitalsType>()
        var receivedCount = 0
        
        let obs = NotificationCenter.default.addObserver(
            forName: .cxRumNotificationMetrics,
            object: nil,
            queue: .main
        ) { note in
            guard let payload = note.object as? CXMobileVitals else { return }
            
            // 1) For the first tick, remember UUID; subsequent notifications must match it
            if firstTickUUID == nil {
                firstTickUUID = payload.uuid
            } else if payload.uuid != firstTickUUID {
                // Ignore metrics from other ticks
                return
            }
            
            // 2) Validate type & value are well-formed
            XCTAssertTrue(
                payload.type == .cpuUsagePercent ||
                payload.type == .totalCpuTimeMs ||
                payload.type == .mainThreadCpuTimeMs,
                "Unexpected metric type: \(payload.type)"
            )
            
            // Value is formatted as a String — ensure it’s numeric
            XCTAssertNotNil(Double(payload.value), "Metric value is not a number: \(payload.value)")
            
            // Track which types we got for this uuid
            if receivedTypes.insert(payload.type).inserted {
                receivedCount += 1
            }
            
            if receivedCount == 3 {
                expect.fulfill()
            }
        }
        
        // Start the monitor
        cpuDetector.startMonitoring()
        
        wait(for: [expect], timeout: 3.0)
        NotificationCenter.default.removeObserver(obs)
    }
    
    func testStopMonitoringPreventsFurtherEmissions() {
        // We’ll capture the first 3 metrics (one tick), then stop, then assert we don’t get more.
        let firstTick = expectation(description: "Got first tick (3 metrics)")
        firstTick.expectedFulfillmentCount = 1
        
        let noFurther = expectation(description: "No further metrics after stop")
        noFurther.isInverted = true // We expect NOT to be fulfilled
        
        var firstTickUUID: String?
        var receivedTypes = Set<CXMobileVitalsType>()
        var totalNotificationsAfterStop = 0
        
        let obs = NotificationCenter.default.addObserver(
            forName: .cxRumNotificationMetrics,
            object: nil,
            queue: .main
        ) { note in
            guard let payload = note.object as? CXMobileVitals else { return }
            
            if firstTickUUID == nil {
                firstTickUUID = payload.uuid
            }
            
            if payload.uuid == firstTickUUID {
                _ = receivedTypes.insert(payload.type)
                if receivedTypes.count == 3 {
                    // We’ve completed one tick; stop monitoring immediately.
                    self.cpuDetector.stopMonitoring()
                    firstTick.fulfill()
                }
                return
            }
            
            // Any notifications with a different UUID would indicate another tick — should not happen after stop.
            totalNotificationsAfterStop += 1
            if totalNotificationsAfterStop > 0 {
                noFurther.fulfill() // This will fail because it's inverted
            }
        }
        
        cpuDetector.startMonitoring()
        
        // Wait for first tick to complete (3 metrics), then ensure no more arrive within a grace window
        wait(for: [firstTick], timeout: 3.0)
        
        // Allow a small window to detect stray posts after stop
        wait(for: [noFurther], timeout: 0.6)
        
        NotificationCenter.default.removeObserver(obs)
    }
}

