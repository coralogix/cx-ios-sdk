//
//  TimeIntervalExtensionTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 02/04/2025.
//

import XCTest
import Foundation
@testable import Coralogix

final class TimeIntervalExtensionTests: XCTestCase {
    
    func testSecondsRounding() {
        XCTAssertEqual(TimeInterval(1.4).seconds, 1)
        XCTAssertEqual(TimeInterval(1.5).seconds, 2)
        XCTAssertEqual(TimeInterval(2.6).seconds, 3)
        XCTAssertEqual(TimeInterval(0).seconds, 0)
    }

    func testMilliseconds() {
        XCTAssertEqual(TimeInterval(1).milliseconds, 1000)
        XCTAssertEqual(TimeInterval(1.234).milliseconds, 1234)
        XCTAssertEqual(TimeInterval(0).milliseconds, 0)
    }

    func testOpenTelemetryFormatValid() {
        let time: TimeInterval = 1.23456789
        let result = time.openTelemetryFormat
        XCTAssertEqual(result[0], 1)
        XCTAssertEqual(result[1], 234_567_890)  // nanoseconds
    }

    func testOpenTelemetryFormatZero() {
        let time: TimeInterval = 0
        let result = time.openTelemetryFormat
        XCTAssertEqual(result, [0, 0])
    }

    func testOpenTelemetryFormatNegative() {
        let time: TimeInterval = -1.5
        let result = time.openTelemetryFormat
        XCTAssertEqual(result, [0, 0])
    }

    func testOpenTelemetryFormatInfinity() {
        let time = Double.infinity
        let result = time.openTelemetryFormat
        XCTAssertEqual(result, [0, 0])
    }

    func testOpenTelemetryFormatNaN() {
        let time = Double.nan
        let result = time.openTelemetryFormat
        XCTAssertEqual(result, [0, 0])
    }
}
