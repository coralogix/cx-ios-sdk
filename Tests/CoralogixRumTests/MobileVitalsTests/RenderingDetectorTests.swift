//
//  RenderingDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 18/09/2025.
//

import XCTest
@testable import Coralogix

class RenderingDetectorTests:  XCTestCase {
    
    func testStatsDictionary_withSampleFPSData_returnsCorrectCalculatedValues() {
        // Given: An instance of the class
        let reporter = FPSDetector()
        
        // And a set of sample data
        reporter.samples = [58.5, 59.1, 60.0, 57.8, 59.9, 60.0, 55.0, 58.0]
        
        // When: We calculate stats and then get the dictionary
        let stats = reporter.statsDictionary()
        
        // Then: The dictionary should contain the correct calculated values
        
        // Expected values for FPS based on the sample data
        // Sorted: [55.0, 57.8, 58.0, 58.5, 59.1, 59.9, 60.0, 60.0]
        let expectedMinFPS = 55.0
        let expectedMaxFPS = 60.0
        let expectedAvgFPS = (55.0 + 57.8 + 58.0 + 58.5 + 59.1 + 59.9 + 60.0 + 60.0) / 8.0 // 468.3 / 8.0
        let expectedP95FPS = 60.0 // p95 index is Int((8 - 1) * 0.95) = Int(6.65) = 6. Value at index 6 is 60.0.

        XCTAssertEqual(stats[Keys.mobileVitalsUnits.rawValue] as? String, MeasurementUnits.fps.stringValue)
        XCTAssertEqual(stats[Keys.min.rawValue] as? Double, expectedMinFPS)
        XCTAssertEqual(stats[Keys.max.rawValue] as? Double, expectedMaxFPS)
        XCTAssertEqual(stats[Keys.p95.rawValue] as? Double, expectedP95FPS)
        if let actualAvgFPS = stats[Keys.avg.rawValue] as? Double {
            XCTAssertEqual(actualAvgFPS.roundedTo(to: 2), expectedAvgFPS.roundedTo(to: 2), accuracy: 0.0001)
        }
    }
}
