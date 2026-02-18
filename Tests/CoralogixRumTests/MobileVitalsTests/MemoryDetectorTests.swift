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
        memoryDetector = MemoryDetector()
        
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
        XCTAssertGreaterThanOrEqual(m.utilizationPercent, 0,
                                    "utilizationPercent should be ≥ 0 (cap removed per CX-31664)")
        XCTAssertLessThan(m.utilizationPercent, 100,
                          "Under normal conditions, memory utilization should be < 100%")
    }
    
    func testStatsDictionary_withDefaultValues_returnsCorrectDictionary() {
        // Given
        memoryDetector.footprintSamples = [150.0, 180.0, 140.0, 200.0, 165.0]
        memoryDetector.residentSamples = [120.0, 150.0, 110.0, 180.0, 135.0]
        memoryDetector.utilizationSamples = [30.0, 45.0, 25.0, 50.0, 35.0]
        
        // When
        let stats = memoryDetector.statsDictionary()
        
        // Then
        XCTAssertEqual(stats.count, 3)
        
        // Verify Footprint Memory
        guard let footprintMemory = stats[MobileVitalsType.footprintMemory.stringValue] as? [String: Any] else {
            XCTFail("Footprint Memory section is missing or has the wrong type.")
            return
        }
        XCTAssertEqual(footprintMemory[Keys.mobileVitalsUnits.rawValue] as? String, MeasurementUnits.megaBytes.stringValue)
        XCTAssertEqual(footprintMemory[Keys.min.rawValue] as? Double, 140.0)
        XCTAssertEqual(footprintMemory[Keys.max.rawValue] as? Double, 200.0)
        XCTAssertEqual(footprintMemory[Keys.avg.rawValue] as? Double, 167.0)
        XCTAssertEqual(footprintMemory[Keys.p95.rawValue] as? Double, 200.0)

        // Verify Resident Memory
        guard let residentMemory = stats[MobileVitalsType.residentMemory.stringValue] as? [String: Any] else {
            XCTFail("Resident Memory section is missing or has the wrong type.")
            return
        }
        XCTAssertEqual(residentMemory[Keys.mobileVitalsUnits.rawValue] as? String, MeasurementUnits.megaBytes.stringValue)
        XCTAssertEqual(residentMemory[Keys.min.rawValue] as? Double, 110.0)
        XCTAssertEqual(residentMemory[Keys.max.rawValue] as? Double, 180.0)
        XCTAssertEqual(residentMemory[Keys.avg.rawValue] as? Double, 139.0)
        XCTAssertEqual(residentMemory[Keys.p95.rawValue] as? Double, 180.0)

        // Verify Memory Utilization
        guard let memoryUtilization = stats[MobileVitalsType.memoryUtilization.stringValue] as? [String: Any] else {
            XCTFail("Memory Utilization section is missing or has the wrong type.")
            return
        }
        XCTAssertEqual(memoryUtilization[Keys.mobileVitalsUnits.rawValue] as? String, MeasurementUnits.percentage.stringValue)
        XCTAssertEqual(memoryUtilization[Keys.min.rawValue] as? Double, 25.0)
        XCTAssertEqual(memoryUtilization[Keys.max.rawValue] as? Double, 50.0)
        XCTAssertEqual(memoryUtilization[Keys.avg.rawValue] as? Double, 37.0)
        XCTAssertEqual(memoryUtilization[Keys.p95.rawValue] as? Double, 50.0)
    }
}
