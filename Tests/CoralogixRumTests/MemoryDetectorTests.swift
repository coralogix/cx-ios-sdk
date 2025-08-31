//
//  MemoryDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 13/08/2025.
//

import XCTest
@testable import Coralogix

final class MemoryDetectorTests: XCTestCase {
    
    var memoryDetector: MemoryDetector!
    var memoryDetected = false
    
    override func setUp() {
        super.setUp()
        memoryDetector = MemoryDetector(interval: 0.1)
        
        memoryDetector.handleMemoryClosure = { [weak self] in
            self?.memoryDetected = true
        }
    }
    
    override func tearDown() {
        memoryDetector.stopMonitoring()
        memoryDetector = nil
        memoryDetected = false
        super.tearDown()
    }
    
    func testReadMemoryMeasurementReturnsSaneValues() {
        guard let m = MemoryDetector.readMemoryMeasurement() else {
            XCTFail("readMemoryMeasurement() returned nil")
            return
        }
        XCTAssertGreaterThanOrEqual(m.footprintMB, 0, "footprintMB should be ≥ 0")
        XCTAssertGreaterThanOrEqual(m.residentMB, 0, "residentMB should be ≥ 0")
        XCTAssertTrue((0.0...100.0).contains(m.utilizationPercent),
                      "utilizationPercent should be clamped to [0, 100]")
    }
    
//    func testEmitsTwoMetricsForSingleTickWithSameUUID() {
//        // State captured by the handler (declare BEFORE the closure)
//        var firstTickUUID: String?
//        var receivedTypes = Set<MobileVitalsType>()
//        let allowedTypes: Set<MobileVitalsType> = [.residentMemory, .footprintMemory, .memoryUtilization]
//
//        // Expect exactly two distinct memory metrics (same UUID)
//        let exp = expectation(forNotification: .cxRumNotificationMetrics, object: nil) { note in
//            guard let payload = note.object as? MobileVitals else { return false }
//
//            // Lock to first tick's UUID
//            if firstTickUUID == nil { firstTickUUID = payload.uuid }
//            guard payload.uuid == firstTickUUID else { return false }
//
//            // Validate type & numeric value
//            guard allowedTypes.contains(payload.type) else {
//                XCTFail("Unexpected metric type: \(payload.type)")
//                return false
//            }
//            XCTAssertNotNil(Double(payload.value), "Metric value should be numeric: \(payload.value)")
//
//            // Fulfill only on first occurrence of each expected type
//            return receivedTypes.insert(payload.type).inserted
//        }
//        exp.expectedFulfillmentCount = 2
//
//        // Start monitoring
//        let detector = MemoryDetector(interval: 0.1)
//        detector.startMonitoring()
//
//        // Wait for both metrics from the same tick
//        wait(for: [exp], timeout: 3.0)
//
//        detector.stopMonitoring()
//
//        // Final sanity check: got exactly the two expected types
//        XCTAssertEqual(receivedTypes, allowedTypes, "Did not receive exactly the expected two memory metrics for a single tick")
//    }
    
//    func testStopMonitoringPreventsFurtherEmissions() {
//        // --- State captured by the handler (declare BEFORE closure) ---
//        var firstUUID: String?
//        var receivedTypes = Set<MobileVitalsType>()
//        let allowed: Set<MobileVitalsType> = [.residentMemory, .memoryUtilization]
//
//        // We'll create detector after wiring the expectations but *declare* it now to avoid capture-order issues.
//        var detector: MemoryDetector!
//
//        // 1) First tick: expect the two distinct metrics (same UUID)
//        let firstTick = expectation(forNotification: .cxRumNotificationMetrics, object: nil) { note in
//            guard let mv = note.object as? MobileVitals else { return false }
//            guard allowed.contains(mv.type) else { return false }
//
//            if firstUUID == nil { firstUUID = mv.uuid }
//            guard mv.uuid == firstUUID else { return false }
//
//            // Value should be numeric
//            XCTAssertNotNil(Double(mv.value), "Metric value should be numeric: \(mv.value)")
//
//            // Fulfill only once per unique type
//            return receivedTypes.insert(mv.type).inserted
//        }
//        firstTick.expectedFulfillmentCount = 2
//
//        // Use a short interval so the first tick arrives quickly in CI
//        detector = MemoryDetector(interval: 0.1)
//        detector.startMonitoring()
//
//        // Wait until we saw both metrics of the first tick
//        wait(for: [firstTick], timeout: 3.0)
//
//        // 2) Stop monitoring and give a tiny drain for any queued posts
//        detector.stopMonitoring()
//        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
//
//        // 3) After stop: there must be NO further emissions
//        let noFurther = expectation(forNotification: .cxRumNotificationMetrics, object: nil) { _ in
//            // Any notification now would be post-stop → should not happen.
//            return true
//        }
//        noFurther.isInverted = true
//
//        // Brief grace window to catch stray posts after stop
//        wait(for: [noFurther], timeout: 0.6)
//
//        // Final sanity check
//        XCTAssertEqual(receivedTypes, allowed, "First tick did not contain exactly the two expected memory metrics")
//    }
}
