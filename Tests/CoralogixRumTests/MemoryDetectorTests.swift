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
    
    func testEmitsTwoMetricsForSingleTickWithSameUUID() {
        // Expect exactly one complete "tick": two metrics with the same UUID:
        // .residentMemoryMb and .memoryUtilizationPercent
        let tickCompleted = expectation(description: "Received two memory metrics of the same tick (same UUID)")
        
        var firstTickUUID: String?
        var receivedTypes = Set<CXMobileVitalsType>()
        
        let obs = NotificationCenter.default.addObserver(
            forName: .cxRumNotificationMetrics,
            object: nil,
            queue: .main
        ) { note in
            guard let payload = note.object as? CXMobileVitals else { return }
            
            // Remember uuid for the first metric; subsequent metrics must match it
            if firstTickUUID == nil {
                firstTickUUID = payload.uuid
            } else if payload.uuid != firstTickUUID {
                // Ignore metrics from other ticks
                return
            }
            
            // Validate expected types and numeric values
            XCTAssertTrue(
                payload.type == .residentMemoryMb ||
                payload.type == .memoryUtilizationPercent,
                "Unexpected metric type: \(payload.type)"
            )
            XCTAssertNotNil(Double(payload.value), "Metric value should be numeric: \(payload.value)")
            
            let inserted = receivedTypes.insert(payload.type).inserted
            if inserted, receivedTypes.count == 2 {
                tickCompleted.fulfill()
            }
        }
        
        let detector = MemoryDetector(interval: 0.1)
        detector.startMonitoring()
        
        wait(for: [tickCompleted], timeout: 3.0)
        detector.stopMonitoring()
        NotificationCenter.default.removeObserver(obs)
    }
    
    func testStopMonitoringPreventsFurtherEmissions() {
        // Capture first tick (2 metrics), then stop. Ensure no metrics from a new UUID arrive afterwards.
        let firstTickDone = expectation(description: "First tick completed")
        let noFurther = expectation(description: "No further ticks after stop")
        noFurther.isInverted = true // We expect NOT to receive more
        
        var firstTickUUID: String?
        var receivedTypes = Set<CXMobileVitalsType>()
        var sawAnotherTick = false
        
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
                if receivedTypes.count == 2 {
                    firstTickDone.fulfill()
                }
                return
            }
            
            // If we see a different UUID, that indicates a second tick
            sawAnotherTick = true
            noFurther.fulfill()
        }
        
        let detector = MemoryDetector(interval: 0.1)
        detector.startMonitoring()
        
        // Wait for first tick to complete, then stop and ensure silence
        wait(for: [firstTickDone], timeout: 3.0)
        detector.stopMonitoring()
        
        // Allow a short window to catch any stray posts from a new tick
        wait(for: [noFurther], timeout: 0.6)
        NotificationCenter.default.removeObserver(obs)
        
        XCTAssertFalse(sawAnotherTick, "Received metrics from another tick after stopMonitoring()")
    }
}
