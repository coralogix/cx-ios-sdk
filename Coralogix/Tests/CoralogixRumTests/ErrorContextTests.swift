//
//  ErrorContextTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import XCTest
// import OpenTelemetryApi
@testable import Coralogix

final class ErrorContextTests: XCTestCase {
    var mockSpanData: SpanDataProtocol!

    override func setUpWithError() throws {
        let data = [["stack_trace_1": "value_1"], ["stack_trace_2": "value_2"], ["stack_trace_3": "value_3"]]
        let stringArray = Helper.convertArrayToJsonString(array: data)
        mockSpanData = MockSpanData(attributes: [
            Keys.domain.rawValue: AttributeValue("com.example.error"),
            Keys.code.rawValue: AttributeValue("404"),
            Keys.localizedDescription.rawValue: AttributeValue("Not Found"),
            Keys.userInfo.rawValue: AttributeValue("{\"exampleKey\": \"exampleValue\"}"),
            Keys.exceptionType.rawValue: AttributeValue("Fatal"),
            Keys.crashTimestamp.rawValue: AttributeValue("1625097600"),
            Keys.processName.rawValue: AttributeValue("ExampleApp"),
            Keys.applicationIdentifier.rawValue: AttributeValue("com.example.app"),
            Keys.triggeredByThread.rawValue: AttributeValue("1"),
            Keys.originalStackTrace.rawValue: AttributeValue(stringArray),
            Keys.baseAddress.rawValue: AttributeValue("0x1000"),
            Keys.arch.rawValue: AttributeValue("arm64")
        ])
    }

    override func tearDownWithError() throws {
        mockSpanData = nil
    }
    
    func testMyErrorStructInitialization() {
           let errorStruct = ErrorContext(otel: mockSpanData)

           XCTAssertEqual(errorStruct.domain, "com.example.error")
           XCTAssertEqual(errorStruct.code, "404")
           XCTAssertEqual(errorStruct.localizedDescription, "Not Found")
           XCTAssertEqual(errorStruct.userInfo?["exampleKey"] as? String, "exampleValue")
           XCTAssertEqual(errorStruct.exceptionType, "Fatal")
           XCTAssertEqual(errorStruct.crashTimestamp, "1625097600")
           XCTAssertEqual(errorStruct.processName, "ExampleApp")
           XCTAssertEqual(errorStruct.applicationIdentifier, "com.example.app")
           XCTAssertEqual(errorStruct.triggeredByThread, 1)
           XCTAssertEqual(errorStruct.originalStackTrace!.count, 3)
           XCTAssertEqual(errorStruct.baseAddress, "0x1000")
           XCTAssertEqual(errorStruct.arch, "arm64")
    }
    
    func testGetDictionaryWithStackTrace() {
        let data = [["stack_trace_1": "value_1"], ["stack_trace_2": "value_2"], ["stack_trace_3": "value_3"]]
        let stringArray = Helper.convertArrayToJsonString(array: data)
        mockSpanData = MockSpanData(attributes: [
            Keys.exceptionType.rawValue: AttributeValue("Fatal"),
            Keys.crashTimestamp.rawValue: AttributeValue("1625097600"),
            Keys.processName.rawValue: AttributeValue("ExampleApp"),
            Keys.applicationIdentifier.rawValue: AttributeValue("com.myapp"),
            Keys.triggeredByThread.rawValue: AttributeValue("1"),
            Keys.originalStackTrace.rawValue: AttributeValue(stringArray),
            Keys.baseAddress.rawValue: AttributeValue("0x1000000"),
            Keys.arch.rawValue: AttributeValue("x86_64")
        ])
        
        let errorStruct = ErrorContext(otel: mockSpanData)
        
        let dictionary = errorStruct.getDictionary()
        guard let crashContext = dictionary[Keys.crashContext.rawValue] as? [String: Any] else {
            XCTFail("Crash context should be available.")
            return
        }
        
        XCTAssertEqual(crashContext[Keys.exceptionType.rawValue] as? String, "Fatal")
        XCTAssertEqual(crashContext[Keys.arch.rawValue] as? String, "x86_64")
        XCTAssertEqual(crashContext[Keys.baseAddress.rawValue] as? String, "0x1000000")
        XCTAssertEqual(crashContext[Keys.triggeredByThread.rawValue] as? Int, 1)
        XCTAssertEqual(crashContext[Keys.applicationIdentifier.rawValue] as? String, "com.myapp")
        XCTAssertEqual(crashContext[Keys.processName.rawValue] as? String, "ExampleApp")
        XCTAssertEqual(crashContext[Keys.crashTimestamp.rawValue] as? String, "1625097600")
        let stackTrace = crashContext[Keys.originalStackTrace.rawValue] as? [[String: Any]]
        XCTAssertEqual(stackTrace!.count, 3)
    }
    
    
    func testGetDictionaryWithoutStackTrace() {
        
        mockSpanData = MockSpanData(attributes: [
            Keys.domain.rawValue: AttributeValue("com.example.error"),
            Keys.code.rawValue: AttributeValue("404"),
            Keys.localizedDescription.rawValue: AttributeValue("Not Found"),
            Keys.userInfo.rawValue: AttributeValue("{\"exampleKey\": \"exampleValue\"}"),
        ])
        
        let errorStruct = ErrorContext(otel: mockSpanData)

        let dictionary = errorStruct.getDictionary()
        guard let exceptionContext = dictionary[Keys.exceptionContext.rawValue] as? [String: Any] else {
            XCTFail("Exception context should be available.")
            return
        }
        
        XCTAssertEqual(exceptionContext[Keys.domain.rawValue] as? String, "com.example.error")
        XCTAssertEqual(exceptionContext[Keys.userInfo.rawValue] as? [String: String], ["exampleKey": "exampleValue"])
    }
}
