//
//  InstrumentationDataTests.swift
//
//
//  Created by Coralogix Dev Team on 01/08/2024.
//

import XCTest
import Foundation

@testable import Coralogix

final class InstrumentationDataTests: XCTestCase {
    var mockSpan: SpanDataProtocol!
    var statTime: Date!
    var endTime: Date!
    let labels = ["label1": "value1"]

    override func setUpWithError() throws {
        statTime = Date()
        endTime = Date()
        
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
    }
    
    override func tearDownWithError() throws {
        mockSpan = nil
    }
    
    func testInstrumentationDataInitialization() throws {
        let instrumentationData = InstrumentationData(otel: mockSpan, labels: labels)
        XCTAssertNotNil(instrumentationData)
        XCTAssertNotNil(instrumentationData.otelSpan)
        XCTAssertNotNil(instrumentationData.otelResource)
    }
    
    func testGetInstrumentationDataDictionary() {
        let instrumentationData = InstrumentationData(otel: mockSpan, labels: labels)
        let dict = instrumentationData.getDictionary()
        XCTAssertNotNil(dict)
        let otelSpan = instrumentationData.otelSpan
        let otelResource = instrumentationData.otelResource
        XCTAssertEqual(otelSpan.attributes.count, 8)
        XCTAssertEqual(otelResource.attributes.count, 3)
    }
    
    func testOtelSpanInitialization() throws {
        let otelSpan = OtelSpan(otel: mockSpan, labels: labels)
        
        XCTAssertEqual(otelSpan.spanId, "span123")
        XCTAssertEqual(otelSpan.traceId, "trace123")
        XCTAssertEqual(otelSpan.name, "testSpan")
        
        let attributes = otelSpan.attributes
        if let eventType = attributes[Keys.eventType.rawValue] as? AttributeValue {
            XCTAssertEqual(eventType.description, "log")
        }
        
        XCTAssertEqual(otelSpan.attributes["label1"] as? String, "value1")
        
        let (integerPart, fractionalPart) = modf(statTime.timeIntervalSince1970)
        XCTAssertEqual(otelSpan.startTime[0], UInt64(integerPart))
        XCTAssertEqual(otelSpan.startTime[1], UInt64((fractionalPart * 1_000_000_000).rounded()))
        
        let (integerPartEnd, fractionalPartEnd) = modf(endTime.timeIntervalSince1970)
        XCTAssertEqual(otelSpan.endTime[0], UInt64(integerPartEnd))
        XCTAssertEqual(otelSpan.endTime[1], UInt64((fractionalPartEnd * 1_000_000_000).rounded()))
        
        XCTAssertEqual(otelSpan.status["status"] as? String, "ok")
        XCTAssertEqual(otelSpan.kind, 1)
    }

    func testGetOtelSpanDictionary() {
        let otelSpan = OtelSpan(otel: mockSpan, labels: nil)
        let dictionary = otelSpan.getDictionary()
        
        XCTAssertEqual(dictionary[Keys.spanId.rawValue] as? String, "span123")
        XCTAssertEqual(dictionary[Keys.traceId.rawValue] as? String, "trace123")
        XCTAssertEqual(dictionary[Keys.name.rawValue] as? String, "testSpan")
        XCTAssertEqual(dictionary[Keys.kind.rawValue] as? Int, 1)
        XCTAssertNotNil(dictionary[Keys.startTime.rawValue])
        XCTAssertNotNil(dictionary[Keys.endTime.rawValue])
        XCTAssertNotNil(dictionary[Keys.status.rawValue])
        XCTAssertNotNil(dictionary[Keys.duration.rawValue])
    }
    
    func testInitializationWithAttributes() {
        let otelResource = OtelResource(otel: mockSpan)
        if let elemet1 = otelResource.attributes["a"] as? AttributeValue {
            XCTAssertEqual(elemet1.description, "1")
        }
        if let elemet2 = otelResource.attributes["b"] as? AttributeValue {
            XCTAssertEqual(elemet2.description, "2")
        }
    }

    func testInitializationWithEmptyAttributes() {
        let mockSpan = MockSpanData(attributes:[:])
        let otelResource = OtelResource(otel: mockSpan)
        XCTAssertTrue(otelResource.attributes.isEmpty)
    }
    
    func testGetOtelResourceDictionary() {
        let otelResource = OtelResource(otel: mockSpan)
        let dict = otelResource.getDictionary()
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict.count, 1)
        if let attributes = dict[Keys.attributes.rawValue] as? [String: Any] {
            XCTAssertNotNil(attributes)
            XCTAssertEqual(attributes.count, 3)
        } else {
            XCTFail("Missing resources")
        }
    }
}

