//
//  HelperTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 26/06/2025.
//

import XCTest
@testable import Coralogix

final class HelperTests: XCTestCase {
    var mockSpan: SpanDataProtocol!
    var statTime: Date!
    var endTime: Date!
    
    override func setUp() {
        statTime = Date()
        endTime = Date()
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             Keys.customTraceId.rawValue: AttributeValue("attr-trace-id"),
                                             Keys.customSpanId.rawValue: AttributeValue("attr-span-id")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testReturnsAttributeTraceAndSpanIdWhenAvailableAndNotEmpty() {
        let result = Helper.getTraceAndSpanId(otel: mockSpan)
        
        XCTAssertEqual(result.traceId, "attr-trace-id")
        XCTAssertEqual(result.spanId, "attr-span-id")
    }

    func testReturnsFallbackWhenAttributesMissing() {
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             Keys.traceId.rawValue: AttributeValue("attr-trace-id"),
                                             Keys.spanId.rawValue: AttributeValue("attr-span-id")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        let result = Helper.getTraceAndSpanId(otel: mockSpan)
        
        XCTAssertEqual(result.traceId, "trace123")
        XCTAssertEqual(result.spanId, "span123")
    }

        func testReturnsFallbackWhenAttributesAreEmptyStrings() {
            mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                 Keys.eventType.rawValue: AttributeValue("log"),
                                                 Keys.source.rawValue: AttributeValue("console"),
                                                 Keys.environment.rawValue: AttributeValue("prod"),
                                                 Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                                 Keys.customTraceId.rawValue: AttributeValue(""),
                                                 Keys.customSpanId.rawValue: AttributeValue("")],
                                    startTime: statTime, endTime: endTime, spanId: "span123",
                                    traceId: "trace123", name: "testSpan", kind: 1,
                                    statusCode: ["status": "ok"],
                                    resources: ["a": AttributeValue("1"),
                                                "b": AttributeValue("2"),
                                                "c": AttributeValue("3")])
            let result = Helper.getTraceAndSpanId(otel: mockSpan)
            
            XCTAssertEqual(result.traceId, "trace123")
            XCTAssertEqual(result.spanId, "span123")
        }
}
    
