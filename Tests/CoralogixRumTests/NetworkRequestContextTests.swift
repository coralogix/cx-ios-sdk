//
//  EventTypeContextTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class NetworkRequestContextTests: XCTestCase {
    var mockSpanData: SpanDataProtocol!

    override func setUpWithError() throws {
        mockSpanData = MockSpanData(attributes: [
            SemanticAttributes.httpMethod.rawValue: AttributeValue("GET"),
            SemanticAttributes.httpStatusCode.rawValue: AttributeValue("200"),
            SemanticAttributes.httpUrl.rawValue: AttributeValue("https://example.com"),
            SemanticAttributes.httpTarget.rawValue: AttributeValue("/home"),
            SemanticAttributes.netPeerName.rawValue: AttributeValue("example.com"),
            SemanticAttributes.httpScheme.rawValue: AttributeValue("https"),
            SemanticAttributes.httpResponseBodySize.rawValue: AttributeValue("1024")
        ], status: "OK", endTime: Date())
    }

    override func tearDownWithError() throws {
        mockSpanData = nil
    }

    func testEventTypeContextInitialization() {
            // Initialize EventTypeContext with mock SpanData
            let context = NetworkRequestContext(otel: mockSpanData)
            
            // Verify the initialization
            XCTAssertEqual(context.method, "GET")
            XCTAssertEqual(context.statusCode, 200)
            XCTAssertEqual(context.url, "https://example.com")
            XCTAssertEqual(context.fragments, "/home")
            XCTAssertEqual(context.host, "example.com")
            XCTAssertEqual(context.schema, "https")
            XCTAssertEqual(context.responseContentLength, 1024)
            XCTAssertNotNil(context.duration)
        }
        
        func testGetDictionary() {
            let context = NetworkRequestContext(otel: mockSpanData)
            
            let dictionary = context.getDictionary()
            
            // Verify dictionary content
            XCTAssertEqual(dictionary[Keys.method.rawValue] as? String, "GET")
            XCTAssertEqual(dictionary[Keys.statusCode.rawValue] as? Int, 200)
            XCTAssertEqual(dictionary[Keys.url.rawValue] as? String, "https://example.com")
            XCTAssertEqual(dictionary[Keys.fragments.rawValue] as? String, "/home")
            XCTAssertEqual(dictionary[Keys.host.rawValue] as? String, "example.com")
            XCTAssertEqual(dictionary[Keys.schema.rawValue] as? String, "https")
            XCTAssertEqual(dictionary[Keys.responseContentLength.rawValue] as? Int, 1024)
            XCTAssertNotNil(dictionary[Keys.duration.rawValue])
        }

    // MARK: - Capture-rule fields: omitted when nil

    func testGetDictionary_captureFieldsAbsentByDefault() {
        let context = NetworkRequestContext(otel: mockSpanData)
        let dict = context.getDictionary()
        XCTAssertNil(dict[Keys.requestHeaders.rawValue],  "requestHeaders must be absent when nil")
        XCTAssertNil(dict[Keys.responseHeaders.rawValue], "responseHeaders must be absent when nil")
        XCTAssertNil(dict[Keys.requestPayload.rawValue],  "requestPayload must be absent when nil")
        XCTAssertNil(dict[Keys.responsePayload.rawValue], "responsePayload must be absent when nil")
    }

    func testGetDictionary_requestHeaders_includedWhenSet() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.requestHeaders = ["Authorization": "Bearer token", "X-Custom": "value"]
        let dict = context.getDictionary()
        let headers = dict[Keys.requestHeaders.rawValue] as? [String: String]
        XCTAssertEqual(headers, ["Authorization": "Bearer token", "X-Custom": "value"])
    }

    func testGetDictionary_responseHeaders_includedWhenSet() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.responseHeaders = ["Content-Type": "application/json"]
        let dict = context.getDictionary()
        let headers = dict[Keys.responseHeaders.rawValue] as? [String: String]
        XCTAssertEqual(headers, ["Content-Type": "application/json"])
    }

    func testGetDictionary_requestPayload_includedWhenSet() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.requestPayload = "{\"key\":\"value\"}"
        let dict = context.getDictionary()
        XCTAssertEqual(dict[Keys.requestPayload.rawValue] as? String, "{\"key\":\"value\"}")
    }

    func testGetDictionary_responsePayload_includedWhenSet() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.responsePayload = "{\"result\":\"ok\"}"
        let dict = context.getDictionary()
        XCTAssertEqual(dict[Keys.responsePayload.rawValue] as? String, "{\"result\":\"ok\"}")
    }

    func testGetDictionary_partialCaptureFields_onlyPresentOnesIncluded() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.requestHeaders = ["X-Req": "yes"]
        // responseHeaders, requestPayload, responsePayload remain nil
        let dict = context.getDictionary()
        XCTAssertNotNil(dict[Keys.requestHeaders.rawValue],  "requestHeaders should be present")
        XCTAssertNil(dict[Keys.responseHeaders.rawValue],    "responseHeaders should be absent")
        XCTAssertNil(dict[Keys.requestPayload.rawValue],     "requestPayload should be absent")
        XCTAssertNil(dict[Keys.responsePayload.rawValue],    "responsePayload should be absent")
    }

    func testRequestPayload_truncatedTo1024Chars() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.requestPayload = String(repeating: "a", count: 2000)
        XCTAssertEqual(context.requestPayload?.count, 1024,
                       "requestPayload exceeding 1024 chars must be truncated to exactly 1024")
    }

    func testResponsePayload_truncatedTo1024Chars() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.responsePayload = String(repeating: "b", count: 1500)
        XCTAssertEqual(context.responsePayload?.count, 1024,
                       "responsePayload exceeding 1024 chars must be truncated to exactly 1024")
    }

    func testRequestPayload_underLimit_notTruncated() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.requestPayload = String(repeating: "x", count: 512)
        XCTAssertEqual(context.requestPayload?.count, 512,
                       "requestPayload under 1024 chars must not be modified")
    }

    func testResponsePayload_exactlyAtLimit_notTruncated() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.responsePayload = String(repeating: "y", count: 1024)
        XCTAssertEqual(context.responsePayload?.count, 1024,
                       "responsePayload exactly 1024 chars must not be truncated")
    }

    func testRequestPayload_exactlyAtLimit_notTruncated() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.requestPayload = String(repeating: "z", count: 1024)
        XCTAssertEqual(context.requestPayload?.count, 1024,
                       "requestPayload exactly 1024 chars must not be truncated")
    }

    func testGetDictionary_requestPayload_truncatedValueSerialised() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.requestPayload = String(repeating: "a", count: 2000)
        let dict = context.getDictionary()
        let serialised = dict[Keys.requestPayload.rawValue] as? String
        XCTAssertEqual(serialised?.count, 1024,
                       "getDictionary must serialise the already-truncated value, not the original")
    }

    func testGetDictionary_responsePayload_truncatedValueSerialised() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.responsePayload = String(repeating: "b", count: 2000)
        let dict = context.getDictionary()
        let serialised = dict[Keys.responsePayload.rawValue] as? String
        XCTAssertEqual(serialised?.count, 1024,
                       "getDictionary must serialise the already-truncated value, not the original")
    }

    func testGetDictionary_allCaptureFieldsSet_allIncluded() {
        var context = NetworkRequestContext(otel: mockSpanData)
        context.requestHeaders  = ["Authorization": "Bearer t"]
        context.responseHeaders = ["Content-Type": "application/json"]
        context.requestPayload  = "req-body"
        context.responsePayload = "res-body"
        let dict = context.getDictionary()
        XCTAssertEqual(dict[Keys.requestHeaders.rawValue]  as? [String: String], ["Authorization": "Bearer t"])
        XCTAssertEqual(dict[Keys.responseHeaders.rawValue] as? [String: String], ["Content-Type": "application/json"])
        XCTAssertEqual(dict[Keys.requestPayload.rawValue]  as? String, "req-body")
        XCTAssertEqual(dict[Keys.responsePayload.rawValue] as? String, "res-body")
    }
}
