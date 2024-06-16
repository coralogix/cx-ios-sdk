//
//  EventContextTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import XCTest
import OpenTelemetrySdk
import OpenTelemetryApi
@testable import Coralogix

final class EventContextTests: XCTestCase {
    var mockSpanData: SpanDataProtocol!

    override func setUpWithError() throws {
        mockSpanData = MockSpanData(attributes: [
            Keys.eventType.rawValue: AttributeValue("error"),
            Keys.source.rawValue: AttributeValue("userAction"),
            Keys.severity.rawValue: AttributeValue("5")
        ])
    }

    override func tearDownWithError() throws {
        mockSpanData = nil
    }

    func testEventContextInitialization() {
            // Initialize EventContext with mock SpanData
            let context = EventContext(otel: mockSpanData)
            
            // Verify the properties are set correctly
            XCTAssertEqual(context.type.rawValue, CoralogixEventType.error.rawValue)
            XCTAssertEqual(context.source, "userAction")
            XCTAssertEqual(context.severity, 5)
        }

        func testEventContextWithUnknownType() {
            // Create mock SpanData with an unknown event type
            let attributes: [String: Any] = [
                Keys.eventType.rawValue: AttributeValue("unknown"),
                Keys.source.rawValue: AttributeValue("userAction"),
                Keys.severity.rawValue: AttributeValue("5")
            ]
            mockSpanData = MockSpanData(attributes: attributes)
            
            // Initialize EventContext
            let context = EventContext(otel: mockSpanData)
            
            // The type should default to .unknown
            XCTAssertEqual(context.type, CoralogixEventType.unknown)
        }

        func testEventContextWithMalformedData() {
            // Mock data with a non-integer severity value
            let attributes: [String: Any] = [
                Keys.eventType.rawValue: AttributeValue("loginEvent"),
                Keys.source.rawValue: AttributeValue("userAction"),
                Keys.severity.rawValue: AttributeValue("severe")
            ]
            let mockSpanData = MockSpanData(attributes: attributes)
            
            // Initialize EventContext
            let context = EventContext(otel: mockSpanData)
            
            // Severity should fallback to 0
            XCTAssertEqual(context.severity, 0)
        }

        func testGetDictionary() {
            // Using a valid setup to test dictionary output
            let attributes: [String: Any] = [
                Keys.eventType.rawValue: AttributeValue("log"),
                Keys.source.rawValue: AttributeValue("userAction"),
                Keys.severity.rawValue: AttributeValue("3")
            ]
            mockSpanData = MockSpanData(attributes: attributes)
            let context = EventContext(otel: mockSpanData)
            
            // Generate dictionary
            let dictionary = context.getDictionary()
            
            // Check dictionary content
            XCTAssertEqual(dictionary[Keys.type.rawValue] as? String, CoralogixEventType.log.rawValue)
            XCTAssertEqual(dictionary[Keys.source.rawValue] as? String, "userAction")
            XCTAssertEqual(dictionary[Keys.severity.rawValue] as? Int, 3)
        }
}
