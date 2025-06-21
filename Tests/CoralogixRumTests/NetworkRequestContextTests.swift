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
            XCTAssertEqual(context.responseContentLength, "1024")
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
            XCTAssertEqual(dictionary[Keys.responseContentLength.rawValue] as? String, "1024")
            XCTAssertNotNil(dictionary[Keys.duration.rawValue])
        }
}
