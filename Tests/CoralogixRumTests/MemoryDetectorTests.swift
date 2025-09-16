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
        XCTAssertTrue((0.0...100.0).contains(m.utilizationPercent),
                      "utilizationPercent should be clamped to [0, 100]")
    }
}
