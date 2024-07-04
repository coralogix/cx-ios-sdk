//
//  ErrorContextTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import XCTest
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
           XCTAssertEqual(errorStruct.baseAddress, "0x1000")
           XCTAssertEqual(errorStruct.arch, "arm64")
    }
    
    func testGetDictionaryWithStackTrace() {
        let trace = """
#0      throwExceptionInDart (package:coralogix_sdk/main.dart:134:5)
#1      _MyAppState.build.<anonymous closure> (package:coralogix_sdk/main.dart:121:32)
#2      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1171:21)
#3      GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:344:24)
#4      TapGestureRecognizer.handleTapUp (package:flutter/src/gestures/tap.dart:652:11)
#5      BaseTapGestureRecognizer._checkUp (package:flutter/src/gestures/tap.dart:309:5)
#6      BaseTapGestureRecognizer.acceptGesture (package:flutter/src/gestures/tap.dart:279:7)
#7      GestureArenaManager.sweep (package:flutter/src/gestures/arena.dart:167:27)
#8      GestureBinding.handleEvent (package:flutter/src/gestures/binding.dart:499:20)
#9      GestureBinding.dispatchEvent (package:flutter/src/gestures/binding.dart:475:22)
#10     RendererBinding.dispatchEvent (package:flutter/src/rendering/binding.dart:425:11)
#11     GestureBinding.<…>
"""
        let stackTraceArray = Helper.parseStackTrace(trace)
        mockSpanData = MockSpanData(attributes: [
            Keys.localizedDescription.rawValue: AttributeValue("localizedDescription"),
            Keys.code.rawValue: AttributeValue("0"),
            Keys.domain.rawValue: AttributeValue(""),
            Keys.stackTrace.rawValue: AttributeValue(Helper.convertArrayToJsonString(array: stackTraceArray)),
        ])
        let errorStruct = ErrorContext(otel: mockSpanData)
        let dictionary = errorStruct.getDictionary()
        guard let exceptionContext = dictionary[Keys.exceptionContext.rawValue] as? [String: Any] else {
            XCTFail("Exception Context should be available.")
            return
        }
        
        if let stackTrace = exceptionContext[Keys.originalStackTrace.rawValue] as? [[String: Any]] {
            XCTAssertEqual(10, stackTrace.count)
            let frame0 = stackTrace[0]
            XCTAssertEqual("package:coralogix_sdk/main.dart", frame0["fileName"] as? String ?? "")
            XCTAssertEqual(5, frame0["columnNumber"] as? Int ?? 0)
            XCTAssertEqual(134, frame0["lineNumber"] as? Int ?? 0)
            XCTAssertEqual("throwExceptionInDart", frame0["functionName"] as? String ?? "")
        }
        
        XCTAssertEqual(exceptionContext[Keys.localizedDescription.rawValue] as? String, "localizedDescription")
        XCTAssertEqual(exceptionContext[Keys.domain.rawValue] as? String, "")
        XCTAssertEqual(exceptionContext[Keys.code.rawValue] as? String, "0")
    }
    
//    func testGetDictionaryWithStackTrace() {
//        let data = [["stack_trace_1": "value_1"], ["stack_trace_2": "value_2"], ["stack_trace_3": "value_3"]]
//        let stringArray = Helper.convertArrayToJsonString(array: data)
//        mockSpanData = MockSpanData(attributes: [
//            Keys.exceptionType.rawValue: AttributeValue("Fatal"),
//            Keys.crashTimestamp.rawValue: AttributeValue("1625097600"),
//            Keys.processName.rawValue: AttributeValue("ExampleApp"),
//            Keys.applicationIdentifier.rawValue: AttributeValue("com.myapp"),
//            Keys.triggeredByThread.rawValue: AttributeValue("1"),
//            Keys.originalStackTrace.rawValue: AttributeValue(stringArray),
//            Keys.baseAddress.rawValue: AttributeValue("0x1000000"),
//            Keys.arch.rawValue: AttributeValue("x86_64")
//        ])
//        
//        let errorStruct = ErrorContext(otel: mockSpanData)
//        
//        let dictionary = errorStruct.getDictionary()
//        guard let exceptionContext = dictionary[Keys.exceptionContext.rawValue] as? [String: Any],
//              let crashContext = exceptionContext[Keys.crashContext.rawValue] as? [String: Any] else {
//            XCTFail("Crash context should be available.")
//            return
//        }
//        
//        XCTAssertEqual(crashContext[Keys.exceptionType.rawValue] as? String, "Fatal")
//        XCTAssertEqual(crashContext[Keys.arch.rawValue] as? String, "x86_64")
//        XCTAssertEqual(crashContext[Keys.baseAddress.rawValue] as? String, "0x1000000")
//        XCTAssertEqual(crashContext[Keys.triggeredByThread.rawValue] as? Int, 1)
//        XCTAssertEqual(crashContext[Keys.applicationIdentifier.rawValue] as? String, "com.myapp")
//        XCTAssertEqual(crashContext[Keys.processName.rawValue] as? String, "ExampleApp")
//        XCTAssertEqual(crashContext[Keys.crashTimestamp.rawValue] as? String, "1625097600")
//        let stackTrace = crashContext[Keys.originalStackTrace.rawValue] as? [[String: Any]]
//        XCTAssertEqual(stackTrace!.count, 3)
//    }
    
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
