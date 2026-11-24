//
//  LogContextTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import XCTest

@testable import Coralogix

final class LogContextTests: XCTestCase {
    var mockSpanData: SpanDataProtocol!

    override func setUpWithError() throws {
        mockSpanData = MockSpanData(attributes: [Keys.message.rawValue: AttributeValue("Test Message"),
                                                 Keys.data.rawValue: AttributeValue("{\"key\": \"value\"}")])
    }

    override func tearDownWithError() throws {
        mockSpanData = nil
    }

    func testGetDictionary() {
        let logContext = LogContext(otel: mockSpanData)
        let dictionary = logContext.getDictionary()
        
        // Assertions
        XCTAssertEqual(dictionary[Keys.message.rawValue] as? String, "Test Message", "Dictionary should contain the correct message.")
        XCTAssertEqual((dictionary[Keys.data.rawValue] as? [String: Any])?["key"] as? String, "value", "Dictionary should contain the correct data.")
    }
}
