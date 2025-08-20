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
        // State captured by the handler (must be declared before the closure)
        var firstTickUUID: String?
        var receivedTypes = Set<MobileVitalsType>()
        let allowedTypes: Set<MobileVitalsType> = [.cpuUsage, .totalCpuTime, .mainThreadCpuTime]

        let exp = expectation(forNotification: .cxRumNotificationMetrics, object: nil) { note in
            guard let payload = note.object as? MobileVitals else { return false }

            // Enforce same UUID for the first observed tick
            if firstTickUUID == nil {
                firstTickUUID = payload.uuid
            } else if payload.uuid != firstTickUUID {
                // Different tick — don't fulfill
                return false
            }

            // Validate type
            guard allowedTypes.contains(payload.type) else {
                XCTFail("Unexpected metric type: \(payload.type)")
                return false
            }

            // Validate value is numeric
            XCTAssertNotNil(Double(payload.value), "Metric value is not a number: \(payload.value)")

            // Fulfill only the first time we see each expected type
            let inserted = receivedTypes.insert(payload.type).inserted
            return inserted
        }

        exp.expectedFulfillmentCount = 3

        // Start the monitor
        cpuDetector.startMonitoring()

        // Wait for exactly three matching notifications
        wait(for: [exp], timeout: 3.0)

        // Final assertions for clarity
        XCTAssertEqual(receivedTypes, allowedTypes, "Did not receive the exact set of CPU metrics")
    }
    
    func testStopMonitoringPreventsFurtherEmissions() {
        // --- State captured by the handler (declare BEFORE closures) ---
        var firstTickUUID: String?
        var receivedTypes = Set<MobileVitalsType>()
        let allowedTypes: Set<MobileVitalsType> = [.cpuUsage, .totalCpuTime, .mainThreadCpuTime]

        // --- 1) Expect exactly the 3 distinct metrics (same UUID) for the first tick ---
        let firstTickThree = expectation(forNotification: .cxRumNotificationMetrics, object: nil) { note in
            guard let payload = note.object as? MobileVitals else { return false }

            // Lock to the first tick's UUID
            if firstTickUUID == nil { firstTickUUID = payload.uuid }
            guard payload.uuid == firstTickUUID else { return false }

            // Validate type & value
            guard allowedTypes.contains(payload.type) else {
                XCTFail("Unexpected metric type: \(payload.type)")
                return false
            }
            XCTAssertNotNil(Double(payload.value), "Metric value is not a number: \(payload.value)")

            // Count only the first time we see each expected type
            let inserted = receivedTypes.insert(payload.type).inserted
            if inserted, receivedTypes.count == 3 {
                // Completed one tick; stop further emissions immediately
                self.cpuDetector.stopMonitoring()
            }
            return inserted // fulfill for unique types only
        }
        firstTickThree.expectedFulfillmentCount = 3

        // Start
        cpuDetector.startMonitoring()

        // Wait for the first tick to complete (3 distinct metrics)
        wait(for: [firstTickThree], timeout: 3.0)

        // --- 2) After stop, ensure no further emissions within a small grace window ---
        // Create the inverted expectation *after* stopping, so it only observes post-stop.
        let noFurtherAfterStop = expectation(forNotification: .cxRumNotificationMetrics, object: nil) { _ in
            // Any notification now would be post-stop → should not happen.
            return true
        }
        noFurtherAfterStop.isInverted = true

        // Short grace window to catch any stray posts after stopMonitoring()
        wait(for: [noFurtherAfterStop], timeout: 0.6)
    }
}

