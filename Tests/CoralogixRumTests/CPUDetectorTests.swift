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
        // Serialize state touched by the notification handler
        let stateQ = DispatchQueue(label: "test.state.q")
        var firstTickUUID: String?
        var receivedTypes = Set<MobileVitalsType>()
        let allowed: Set<MobileVitalsType> = [.cpuUsage, .totalCpuTime, .mainThreadCpuTime]

        // 1) Expect exactly 3 distinct metric types for the first batch
        let firstThree = expectation(forNotification: .cxRumNotificationMetrics, object: nil) { note in
            guard let payload = note.object as? MobileVitals else { return false }

            // serialize mutations/reads
            return stateQ.sync {
                if firstTickUUID == nil { firstTickUUID = payload.uuid }
                // If UUID grouping is not guaranteed, comment the next line out:
                guard payload.uuid == firstTickUUID else { return false }

                guard allowed.contains(payload.type) else {
                    XCTFail("Unexpected metric type: \(payload.type)")
                    return false
                }
                XCTAssertNotNil(Double(payload.value), "Non-numeric value: \(payload.value)")

                // count unique types
                let inserted = receivedTypes.insert(payload.type).inserted
                if inserted, receivedTypes.count == 3 {
                    // do not stop here—invert expectation will be armed AFTER we drain
                }
                return inserted
            }
        }
        firstThree.expectedFulfillmentCount = 3
        firstThree.assertForOverFulfill = false

        // Start after expectation is armed
        cpuDetector.startMonitoring()

        // Wait for the first batch (give CI some headroom)
        wait(for: [firstThree], timeout: 5.0)

        // Now stop monitoring
        cpuDetector.stopMonitoring()

        // Drain: give any in-flight posts time to land BEFORE we arm the inverted expectation
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        // 2) Assert no further emissions after stop within a grace window
        let noneAfterStop = expectation(forNotification: .cxRumNotificationMetrics, object: nil) { _ in
            // Anything now is after stop -> should not happen
            return true
        }
        noneAfterStop.isInverted = true

        wait(for: [noneAfterStop], timeout: 1.0)
    }
}

