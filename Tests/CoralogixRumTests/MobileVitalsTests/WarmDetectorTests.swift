//
//  WarmDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 18/09/2025.
//

import XCTest
import Foundation
import UIKit

@testable import Coralogix

class WarmDetectorTests: XCTestCase {
    var sut: WarmDetector!
    var expectation: XCTestExpectation!
    var mockTime: Double = 0.0
    
    override func setUp() {
        super.setUp()
        sut = WarmDetector()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
  
    // MARK: - startMonitoring() Tests
    
    func testAppDidBecomeActiveNotification_whenWarmStartOccurred_callsClosureWithCorrectValue() {

        // Set a known start time
        sut.foregroundStartTime = 50.0

        var receivedWarmMetric: [String: Any]?
        sut.handleWarmClosure = { metric in
            receivedWarmMetric = metric
        }

        Thread.sleep(forTimeInterval: 2.0)

        sut.appDidBecomeActiveNotification()

        // 3. Then: We assert that the closure was called and the values are correct
        XCTAssertNotNil(receivedWarmMetric, "handleWarmClosure should be called")

        // The expected end time is now the realistic value from the mock
        
        // Check that the foregroundEndTime property was correctly set
        XCTAssertNotNil(sut.foregroundEndTime!)
        
        XCTAssertNotEqual(sut.foregroundEndTime!, 0, "Foreground end time should be set to the current time")

        // Verify the dictionary structure and values
        let dict = receivedWarmMetric?[MobileVitalsType.warm.stringValue] as? [String: Any]
        XCTAssertEqual(dict?["units"] as? String,
                       MeasurementUnits.milliseconds.stringValue,
                       "The units should be milliseconds")

        // The duration calculation is based on the difference, which is still 25.0
        let expectedDuration = (mockTime - sut.foregroundStartTime!) * 1000
        if let value = receivedWarmMetric?[MobileVitalsType.warm.stringValue] as? Double {
            XCTAssertEqual(value,
                           expectedDuration,
                           accuracy: 0.001,
                           "The warm start duration should be calculated correctly")
        }
    }
}
