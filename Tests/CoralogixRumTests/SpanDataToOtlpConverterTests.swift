//
//  SpanDataToOtlpConverterTests.swift
//
//  Created by Coralogix Dev Team on 12/04/2026.
//

import XCTest
import Foundation

@testable import Coralogix

final class SpanDataToOtlpConverterTests: XCTestCase {
    
    // MARK: - Test Data
    
    private func createTestSpanData(
        name: String = "test-span",
        traceId: TraceId = TraceId(idHi: 0x0102030405060708, idLo: 0x090a0b0c0d0e0f10),
        spanId: SpanId = SpanId(id: 0x1112131415161718),
        parentSpanId: SpanId? = nil,
        kind: SpanKind = .client,
        status: Status = .ok,
        startTime: Date = Date(timeIntervalSince1970: 1700000000),
        endTime: Date = Date(timeIntervalSince1970: 1700000001),
        attributes: [String: AttributeValue] = [:],
        resource: Resource = Resource(),
        instrumentationScope: InstrumentationScopeInfo = InstrumentationScopeInfo(name: "test-scope", version: "1.0.0")
    ) -> SpanData {
        let context = SpanContext.create(
            traceId: traceId,
            spanId: spanId,
            traceFlags: TraceFlags(),
            traceState: TraceState()
        )
        
        let span = RecordEventsReadableSpan.startSpan(
            context: context,
            name: name,
            instrumentationScopeInfo: instrumentationScope,
            kind: kind,
            parentContext: parentSpanId.map { parentId in
                SpanContext.create(
                    traceId: traceId,
                    spanId: parentId,
                    traceFlags: TraceFlags(),
                    traceState: TraceState()
                )
            },
            hasRemoteParent: false,
            spanLimits: SpanLimits(),
            spanProcessor: NoopSpanProcessor(),
            clock: MillisClock(),
            resource: resource,
            attributes: AttributesDictionary(capacity: 100),
            links: [],
            totalRecordedLinks: 0,
            startTime: startTime
        )
        
        for (key, value) in attributes {
            span.setAttribute(key: key, value: value)
        }
        span.status = status
        span.end(time: endTime)
        
        return span.toSpanData()
    }
    
    // MARK: - TraceId/SpanId Base64 Encoding Tests
    
    func testEncodeTraceIdToBase64() {
        let traceId = TraceId(idHi: 0x0102030405060708, idLo: 0x090a0b0c0d0e0f10)
        let base64 = SpanDataToOtlpConverter.encodeTraceIdToBase64(traceId)
        
        XCTAssertFalse(base64.isEmpty, "Base64 encoded traceId should not be empty")
        
        guard let data = Data(base64Encoded: base64) else {
            XCTFail("Base64 string should be decodable")
            return
        }
        XCTAssertEqual(data.count, 16, "Decoded traceId should be 16 bytes")
    }
    
    func testEncodeSpanIdToBase64() {
        let spanId = SpanId(id: 0x1112131415161718)
        let base64 = SpanDataToOtlpConverter.encodeSpanIdToBase64(spanId)
        
        XCTAssertFalse(base64.isEmpty, "Base64 encoded spanId should not be empty")
        
        guard let data = Data(base64Encoded: base64) else {
            XCTFail("Base64 string should be decodable")
            return
        }
        XCTAssertEqual(data.count, 8, "Decoded spanId should be 8 bytes")
    }
    
    // MARK: - Time Conversion Tests
    
    func testDateToUnixNanoString() {
        let date = Date(timeIntervalSince1970: 1700000000.123456789)
        let nanoString = SpanDataToOtlpConverter.dateToUnixNanoString(date)
        
        XCTAssertFalse(nanoString.isEmpty, "Nano string should not be empty")
        
        guard let nanos = UInt64(nanoString) else {
            XCTFail("Should be a valid UInt64 string")
            return
        }
        
        let expectedNanos = UInt64(1700000000.123456789 * 1_000_000_000)
        let diff = nanos > expectedNanos ? nanos - expectedNanos : expectedNanos - nanos
        XCTAssertLessThan(diff, 1000, "Nano conversion should be accurate within 1 microsecond")
    }
    
    // MARK: - Single Span Conversion Tests
    
    func testConvertSingleSpan() {
        let spanData = createTestSpanData(
            name: "test-operation",
            kind: .client,
            status: .ok
        )
        
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        XCTAssertEqual(result.resourceSpans.count, 1)
        XCTAssertEqual(result.resourceSpans[0].scopeSpans.count, 1)
        XCTAssertEqual(result.resourceSpans[0].scopeSpans[0].spans.count, 1)
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        XCTAssertEqual(otlpSpan.name, "test-operation")
        XCTAssertEqual(otlpSpan.kind, .client)
        XCTAssertEqual(otlpSpan.status.code, .ok)
    }
    
    // MARK: - Status Conversion Tests
    
    func testConvertStatusOk() {
        let spanData = createTestSpanData(status: .ok)
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        XCTAssertEqual(otlpSpan.status.code, .ok)
        XCTAssertNil(otlpSpan.status.message)
    }
    
    func testConvertStatusUnset() {
        let spanData = createTestSpanData(status: .unset)
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        XCTAssertEqual(otlpSpan.status.code, .unset)
    }
    
    func testConvertStatusError() {
        let spanData = createTestSpanData(status: .error(description: "Something went wrong"))
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        XCTAssertEqual(otlpSpan.status.code, .error)
        XCTAssertEqual(otlpSpan.status.message, "Something went wrong")
    }
    
    // MARK: - SpanKind Conversion Tests
    
    func testConvertSpanKindInternal() {
        let spanData = createTestSpanData(kind: .internal)
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        XCTAssertEqual(otlpSpan.kind, .internal)
    }
    
    func testConvertSpanKindServer() {
        let spanData = createTestSpanData(kind: .server)
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        XCTAssertEqual(otlpSpan.kind, .server)
    }
    
    func testConvertSpanKindClient() {
        let spanData = createTestSpanData(kind: .client)
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        XCTAssertEqual(otlpSpan.kind, .client)
    }
    
    func testConvertSpanKindProducer() {
        let spanData = createTestSpanData(kind: .producer)
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        XCTAssertEqual(otlpSpan.kind, .producer)
    }
    
    func testConvertSpanKindConsumer() {
        let spanData = createTestSpanData(kind: .consumer)
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        XCTAssertEqual(otlpSpan.kind, .consumer)
    }
    
    // MARK: - Attribute Conversion Tests
    
    func testConvertStringAttribute() {
        let spanData = createTestSpanData(
            attributes: ["test.string": .string("hello")]
        )
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        let attr = otlpSpan.attributes.first { $0.key == "test.string" }
        XCTAssertNotNil(attr)
        
        if case .stringValue(let value) = attr?.value {
            XCTAssertEqual(value, "hello")
        } else {
            XCTFail("Expected string value")
        }
    }
    
    func testConvertIntAttribute() {
        let spanData = createTestSpanData(
            attributes: ["test.int": .int(42)]
        )
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        let attr = otlpSpan.attributes.first { $0.key == "test.int" }
        XCTAssertNotNil(attr)
        
        if case .intValue(let value) = attr?.value {
            XCTAssertEqual(value, 42)
        } else {
            XCTFail("Expected int value")
        }
    }
    
    func testConvertDoubleAttribute() {
        let spanData = createTestSpanData(
            attributes: ["test.double": .double(3.14)]
        )
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        let attr = otlpSpan.attributes.first { $0.key == "test.double" }
        XCTAssertNotNil(attr)
        
        if case .doubleValue(let value) = attr?.value {
            XCTAssertEqual(value, 3.14, accuracy: 0.001)
        } else {
            XCTFail("Expected double value")
        }
    }
    
    func testConvertBoolAttribute() {
        let spanData = createTestSpanData(
            attributes: ["test.bool": .bool(true)]
        )
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        let attr = otlpSpan.attributes.first { $0.key == "test.bool" }
        XCTAssertNotNil(attr)
        
        if case .boolValue(let value) = attr?.value {
            XCTAssertTrue(value)
        } else {
            XCTFail("Expected bool value")
        }
    }
    
    func testConvertStringArrayAttribute() {
        let spanData = createTestSpanData(
            attributes: ["test.strings": .stringArray(["a", "b", "c"])]
        )
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        let attr = otlpSpan.attributes.first { $0.key == "test.strings" }
        XCTAssertNotNil(attr)
        
        if case .arrayValue(let values) = attr?.value {
            XCTAssertEqual(values.count, 3)
        } else {
            XCTFail("Expected array value")
        }
    }
    
    // MARK: - Grouping Tests
    
    func testGroupSpansByResource() {
        let resource1 = Resource(attributes: [
            ResourceAttributes.serviceName.rawValue: .string("service-a")
        ])
        let resource2 = Resource(attributes: [
            ResourceAttributes.serviceName.rawValue: .string("service-b")
        ])
        
        let span1 = createTestSpanData(name: "span1", resource: resource1)
        let span2 = createTestSpanData(name: "span2", resource: resource1)
        let span3 = createTestSpanData(name: "span3", resource: resource2)
        
        let result = SpanDataToOtlpConverter.convert(spans: [span1, span2, span3])
        
        XCTAssertEqual(result.resourceSpans.count, 2, "Should have 2 resource groups")
        
        let totalSpans = result.resourceSpans.flatMap { $0.scopeSpans.flatMap { $0.spans } }
        XCTAssertEqual(totalSpans.count, 3, "Should have 3 total spans")
    }
    
    func testGroupSpansByScope() {
        let scope1 = InstrumentationScopeInfo(name: "scope-a", version: "1.0.0")
        let scope2 = InstrumentationScopeInfo(name: "scope-b", version: "2.0.0")
        
        let span1 = createTestSpanData(name: "span1", instrumentationScope: scope1)
        let span2 = createTestSpanData(name: "span2", instrumentationScope: scope1)
        let span3 = createTestSpanData(name: "span3", instrumentationScope: scope2)
        
        let result = SpanDataToOtlpConverter.convert(spans: [span1, span2, span3])
        
        XCTAssertEqual(result.resourceSpans.count, 1, "Should have 1 resource group with default resource")
        XCTAssertEqual(result.resourceSpans[0].scopeSpans.count, 2, "Should have 2 scope groups")
    }
    
    // MARK: - JSON Serialization Tests
    
    func testToJSON() {
        let spanData = createTestSpanData(
            name: "json-test-span",
            attributes: [
                "http.method": .string("GET"),
                "http.status_code": .int(200)
            ]
        )
        
        guard let jsonData = SpanDataToOtlpConverter.toJSON(spans: [spanData]) else {
            XCTFail("JSON encoding should succeed")
            return
        }
        
        XCTAssertGreaterThan(jsonData.count, 0, "JSON data should not be empty")
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Should be valid JSON")
            return
        }
        
        XCTAssertNotNil(jsonObject["resource_spans"], "Should contain resource_spans key")
    }
    
    func testJSONContainsRequiredFields() {
        let spanData = createTestSpanData(name: "field-test")
        
        guard let jsonData = SpanDataToOtlpConverter.toJSON(spans: [spanData]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("JSON encoding should succeed")
            return
        }
        
        XCTAssertTrue(jsonString.contains("trace_id"), "JSON should contain trace_id")
        XCTAssertTrue(jsonString.contains("span_id"), "JSON should contain span_id")
        XCTAssertTrue(jsonString.contains("start_time_unix_nano"), "JSON should contain start_time_unix_nano")
        XCTAssertTrue(jsonString.contains("end_time_unix_nano"), "JSON should contain end_time_unix_nano")
        XCTAssertTrue(jsonString.contains("status"), "JSON should contain status")
        XCTAssertTrue(jsonString.contains("kind"), "JSON should contain kind")
    }
    
    // MARK: - Parent Span ID Tests
    
    func testSpanWithParentSpanId() {
        let parentSpanId = SpanId(id: 0xAABBCCDDEEFF0011)
        let spanData = createTestSpanData(parentSpanId: parentSpanId)
        
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        
        XCTAssertNotNil(otlpSpan.parentSpanId, "Parent span ID should be present")
        XCTAssertFalse(otlpSpan.parentSpanId!.isEmpty, "Parent span ID should not be empty")
    }
    
    func testSpanWithoutParentSpanId() {
        let spanData = createTestSpanData(parentSpanId: nil)
        
        let result = SpanDataToOtlpConverter.convert(spans: [spanData])
        let otlpSpan = result.resourceSpans[0].scopeSpans[0].spans[0]
        
        XCTAssertNil(otlpSpan.parentSpanId, "Parent span ID should be nil for root spans")
    }
    
    // MARK: - Empty Spans Test
    
    func testConvertEmptySpans() {
        let result = SpanDataToOtlpConverter.convert(spans: [])
        
        XCTAssertTrue(result.resourceSpans.isEmpty, "Should return empty resource spans for empty input")
    }
}

