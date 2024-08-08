//
//  InteractionContextTests.swift
//  
//
//  Created by Coralogix Dev Team on 04/08/2024.
//

import XCTest
@testable import Coralogix

final class InteractionContextTests: XCTestCase {
    var mockSpan: SpanDataProtocol!
    var statTime: Date!
    var endTime: Date!
    
    override func setUpWithError() throws {
        statTime = Date()
        endTime = Date()
        let tapObject = [Keys.tapName.rawValue: "UIButton",
                         Keys.attributes.rawValue: [Keys.text.rawValue: "click me"]] as [String : Any]
           mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("user-interaction"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.tapObject.rawValue:AttributeValue( Helper.convertDictionayToJsonString(dict: tapObject))],
                                startTime: statTime,
                                endTime: endTime,
                                spanId: "span123",
                                traceId: "trace123",
                                name: "testSpan",
                                kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
    }

    override func tearDownWithError() throws {
        mockSpan = nil
    }

    func testInitialization() throws {
        let context = InteractionContext(otel: mockSpan)
        XCTAssertEqual(context.elementId, "UIButton")
        XCTAssertEqual(context.eventName, Keys.click.rawValue)
        if let attributes = context.attributes, let text = attributes[Keys.text.rawValue] as? String {
            XCTAssertEqual(text, "click me")
        }
    }
    
    func testGetDictionary() {
        let context = InteractionContext(otel: mockSpan)
        
        let dictionary = context.getDictionary()
        XCTAssertEqual(dictionary[Keys.elementId.rawValue] as? String, "UIButton")
        XCTAssertEqual(dictionary[Keys.eventName.rawValue] as? String, Keys.click.rawValue)
        XCTAssertEqual((dictionary[Keys.attributes.rawValue] as? [String: Any])?["text"] as? String, "click me")
    }
}
