//
//  ScreenshotContextTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 01/07/2025.

import XCTest
@testable import Coralogix

final class ScreenshotContextTests: XCTestCase {
    
    func testInitializationWithValidAttributes() {
        let attributes: [String: Any] = [
            Keys.screenshotId.rawValue: AttributeValue("screenshot_123"),
            Keys.page.rawValue: AttributeValue("5"),
            Keys.isManual.rawValue: AttributeValue(true)
        ]
        let startTime = Date(timeIntervalSince1970: 1234567890)
        let mockData = MockSpanData(attributes: attributes, startTime: startTime)
        
        let context = ScreenshotContext(otel: mockData)
        
        XCTAssertEqual(context.screenshotId, "screenshot_123")
        XCTAssertEqual(context.page, 5)
        XCTAssertEqual(context.segmentTimestamp, 1234567890)
        XCTAssertTrue(context.isManual)
    }
    
    func testInitializationWithMissingAttributes() {
        let attributes: [String: Any] = [:]
        let mockData = MockSpanData(attributes: attributes)
        
        let context = ScreenshotContext(otel: mockData)
        
        XCTAssertEqual(context.screenshotId, Keys.undefined.rawValue)
        XCTAssertEqual(context.page, 0)
        XCTAssertFalse(context.isManual)
    }
    
    func testInitializationWithInvalidPage() {
        let attributes: [String: Any] = [
            Keys.page.rawValue: "invalid_number"
        ]
        let mockData = MockSpanData(attributes: attributes)
        
        let context = ScreenshotContext(otel: mockData)
        
        XCTAssertEqual(context.page, 0)
    }
    
    func testGetDictionaryOutput() {
        let attributes: [String: Any] = [
            Keys.screenshotId.rawValue: AttributeValue("abc"),
            Keys.page.rawValue: AttributeValue("3"),
            Keys.isManual.rawValue: AttributeValue(false)
        ]
        let startTime = Date(timeIntervalSince1970: 1234567890)
        let mockData = MockSpanData(attributes: attributes, startTime: startTime)
        
        let context = ScreenshotContext(otel: mockData)
        let dict = context.getDictionary()
        
        XCTAssertEqual(dict[Keys.screenshotId.rawValue] as? String, "abc")
        XCTAssertEqual(dict[Keys.page.rawValue] as? Int, 3)
        XCTAssertEqual(dict[Keys.isManual.rawValue] as? Bool, false)
        
        let segmentTimestampMs = Int(startTime.timeIntervalSince1970 * 1000)
        XCTAssertEqual(dict[Keys.segmentTimestamp.rawValue] as? Int, segmentTimestampMs)
    }
}
