//
//  ErrorContextTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class ErrorContextTests: XCTestCase {
    var mockSpanData: SpanDataProtocol!

    override func setUpWithError() throws {
        let data = [["stack_trace_1": "value_1"], ["stack_trace_2": "value_2"], ["stack_trace_3": "value_3"]]
        let stringArray = Helper.convertArrayToJsonString(array: data)
        mockSpanData = MockSpanData(attributes: [
            Keys.domain.rawValue: AttributeValue("com.example.error"),
            Keys.code.rawValue: AttributeValue("404"),
            Keys.errorMessage.rawValue: AttributeValue("Not Found"),
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
           XCTAssertEqual(errorStruct.errorMessage, "Not Found")
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
            Keys.errorMessage.rawValue: AttributeValue("localizedDescription"),
            Keys.code.rawValue: AttributeValue("0"),
            Keys.domain.rawValue: AttributeValue(""),
            Keys.stackTrace.rawValue: AttributeValue(Helper.convertArrayToJsonString(array: stackTraceArray)),
        ])
        let errorStruct = ErrorContext(otel: mockSpanData)
        let dictionary = errorStruct.getDictionary()
        
        if let stackTrace = dictionary[Keys.originalStackTrace.rawValue] as? [[String: Any]] {
            XCTAssertEqual(11, stackTrace.count)
            let frame0 = stackTrace[0]
            XCTAssertEqual("package:coralogix_sdk/main.dart", frame0["fileName"] as? String ?? "")
            XCTAssertEqual(5, frame0["columnNumber"] as? Int ?? 0)
            XCTAssertEqual(134, frame0["lineNumber"] as? Int ?? 0)
            XCTAssertEqual("throwExceptionInDart", frame0["functionName"] as? String ?? "")
        }
        
        XCTAssertEqual(dictionary[Keys.errorMessage.rawValue] as? String, "localizedDescription")
        if let domain = dictionary[Keys.domain.rawValue] as? String {
            XCTAssertEqual(domain, "")
        }
        XCTAssertEqual(dictionary[Keys.code.rawValue] as? String, "0")
    }
        
    func testGetDictionaryWithThreads() {
        var threads = [String]()
        var result = [[String: Any]]()
        for i in 0...3 {
            var frameObj = [String: Any]()
            frameObj[Keys.frameNumber.rawValue] = "\(i)"
            frameObj[Keys.binary.rawValue] = "DemoAppSwift"
            frameObj[Keys.functionAddressCalled.rawValue] = "0x0000000104b31f94"
            frameObj[Keys.base.rawValue] = "_$s12DemoAppSwift8CrashSimC15indexOutOfRang92FB97BA4A060F0ABLLyyFZ"
            frameObj[Keys.offset.rawValue] = "224"
            result.append(frameObj)
        }
        threads.append(Helper.convertArrayToJsonString(array: result))
        mockSpanData = MockSpanData(attributes: [
            Keys.threads.rawValue: AttributeValue(Helper.convertArrayOfStringToJsonString(array: threads)),
            Keys.exceptionType.rawValue: AttributeValue("Fatal"),
            Keys.crashTimestamp.rawValue: AttributeValue("1625097600"),
            Keys.processName.rawValue: AttributeValue("ExampleApp"),
            Keys.applicationIdentifier.rawValue: AttributeValue("com.myapp"),
            Keys.triggeredByThread.rawValue: AttributeValue("1"),
            Keys.baseAddress.rawValue: AttributeValue("0x1000000"),
            Keys.arch.rawValue: AttributeValue("x86_64")
        ])
        
        let errorStruct = ErrorContext(otel: mockSpanData)
        let dictionary = errorStruct.getDictionary()
        
        guard let threads = dictionary[Keys.threads.rawValue] as? [[[String: Any]]] else {
            XCTFail("Crash Context should be available.")
            return
        }
        
        if let frames = threads.first,
           let frame = frames.first {
            XCTAssertEqual("DemoAppSwift", frame[Keys.binary.rawValue] as? String)
            XCTAssertEqual("0x0000000104b31f94", frame[Keys.functionAddressCalled.rawValue] as? String)
            XCTAssertEqual("0", frame[Keys.frameNumber.rawValue] as? String)
            XCTAssertEqual("224", frame[Keys.offset.rawValue] as? String)
            XCTAssertEqual("_$s12DemoAppSwift8CrashSimC15indexOutOfRang92FB97BA4A060F0ABLLyyFZ", frame[Keys.base.rawValue] as? String)
        }
        

        XCTAssertEqual(dictionary[Keys.exceptionType.rawValue] as? String, "Fatal")
        XCTAssertEqual(dictionary[Keys.arch.rawValue] as? String, "x86_64")
        XCTAssertEqual(dictionary[Keys.baseAddress.rawValue] as? String, "0x1000000")
        XCTAssertEqual(dictionary[Keys.triggeredByThread.rawValue] as? Int, 1)
        XCTAssertEqual(dictionary[Keys.applicationIdentifier.rawValue] as? String, "com.myapp")
        XCTAssertEqual(dictionary[Keys.processName.rawValue] as? String, "ExampleApp")
        XCTAssertEqual(dictionary[Keys.crashTimestamp.rawValue] as? String, "1625097600")
    }
    
    // MARK: - Obfuscated Dart frame serialization

    func testObfuscatedFrameSerializesWithVirtKey() {
        let frame: [String: Any] = [Keys.virt.rawValue: "0x00000000003da15f"]
        let frames = [frame]
        mockSpanData = MockSpanData(attributes: [
            Keys.errorMessage.rawValue: AttributeValue("StateError: state error try catch"),
            Keys.stackTrace.rawValue: AttributeValue(Helper.convertArrayToJsonString(array: frames)),
            Keys.arch.rawValue: AttributeValue("arm64"),
            Keys.buildId.rawValue: AttributeValue("e4f372b4e5cb2ba87653648d9c509cb1"),
            Keys.stackTraceType.rawValue: AttributeValue("obfuscated")
        ])
        let errorStruct = ErrorContext(otel: mockSpanData)
        let dictionary = errorStruct.getDictionary()

        guard let stackTrace = dictionary[Keys.originalStackTrace.rawValue] as? [[String: Any]] else {
            XCTFail("original_stacktrace should be present")
            return
        }
        XCTAssertEqual(1, stackTrace.count)
        XCTAssertEqual("0x00000000003da15f", stackTrace[0][Keys.virt.rawValue] as? String)
        XCTAssertNil(dictionary[Keys.code.rawValue], "code should not be present in obfuscated Flutter error")
    }

    func testNewFieldsPresentWhenSet() {
        mockSpanData = MockSpanData(attributes: [
            Keys.errorMessage.rawValue: AttributeValue("StateError"),
            Keys.code.rawValue: AttributeValue("0"),
            Keys.domain.rawValue: AttributeValue(""),
            Keys.arch.rawValue: AttributeValue("arm64"),
            Keys.buildId.rawValue: AttributeValue("e4f372b4e5cb2ba87653648d9c509cb1"),
            Keys.stackTraceType.rawValue: AttributeValue("obfuscated")
        ])
        let errorStruct = ErrorContext(otel: mockSpanData)
        let dictionary = errorStruct.getDictionary()

        XCTAssertEqual("arm64", dictionary[Keys.arch.rawValue] as? String)
        XCTAssertEqual("e4f372b4e5cb2ba87653648d9c509cb1", dictionary[Keys.buildId.rawValue] as? String)
        XCTAssertEqual("obfuscated", dictionary[Keys.stackTraceType.rawValue] as? String)
    }

    func testSymbolicatedFrameDoesNotEmitArchOrBuildId() {
        let frames: [[String: Any]] = [
            ["functionName": "throwExceptionInDart", "fileName": "package:coralogix_sdk/main.dart", "lineNumber": 134, "columnNumber": 5]
        ]
        mockSpanData = MockSpanData(attributes: [
            Keys.errorMessage.rawValue: AttributeValue("state error try catch"),
            Keys.stackTrace.rawValue: AttributeValue(Helper.convertArrayToJsonString(array: frames)),
            Keys.stackTraceType.rawValue: AttributeValue("symbolicated")
        ])
        let errorStruct = ErrorContext(otel: mockSpanData)
        let dictionary = errorStruct.getDictionary()

        XCTAssertEqual("symbolicated", dictionary[Keys.stackTraceType.rawValue] as? String)
        XCTAssertNil(dictionary[Keys.arch.rawValue], "arch should be absent for symbolicated frames")
        XCTAssertNil(dictionary[Keys.buildId.rawValue], "build_id should be absent for symbolicated frames")
        XCTAssertNil(dictionary[Keys.code.rawValue], "code should be absent in Flutter error path")
    }

    func testNewFieldsOmittedWhenNil() {
        mockSpanData = MockSpanData(attributes: [
            Keys.errorMessage.rawValue: AttributeValue("Some error"),
            Keys.code.rawValue: AttributeValue("0"),
            Keys.domain.rawValue: AttributeValue("")
        ])
        let errorStruct = ErrorContext(otel: mockSpanData)
        let dictionary = errorStruct.getDictionary()

        XCTAssertNil(dictionary[Keys.buildId.rawValue])
        XCTAssertNil(dictionary[Keys.stackTraceType.rawValue])
        XCTAssertNil(dictionary[Keys.arch.rawValue])
    }

    func testNativeCrashPathUnaffected() {
        var threads = [String]()
        var result = [[String: Any]]()
        var frameObj = [String: Any]()
        frameObj[Keys.frameNumber.rawValue] = "0"
        frameObj[Keys.binary.rawValue] = "DemoAppSwift"
        frameObj[Keys.functionAddressCalled.rawValue] = "0x0000000104b31f94"
        frameObj[Keys.base.rawValue] = "_$s12DemoAppSwift8CrashSimC"
        frameObj[Keys.offset.rawValue] = "224"
        result.append(frameObj)
        threads.append(Helper.convertArrayToJsonString(array: result))

        mockSpanData = MockSpanData(attributes: [
            Keys.threads.rawValue: AttributeValue(Helper.convertArrayOfStringToJsonString(array: threads)),
            Keys.exceptionType.rawValue: AttributeValue("EXC_BAD_ACCESS"),
            Keys.crashTimestamp.rawValue: AttributeValue("1625097600"),
            Keys.processName.rawValue: AttributeValue("DemoApp"),
            Keys.applicationIdentifier.rawValue: AttributeValue("com.myapp"),
            Keys.triggeredByThread.rawValue: AttributeValue("0"),
            Keys.baseAddress.rawValue: AttributeValue("0x1000000"),
            Keys.arch.rawValue: AttributeValue("arm64")
        ])
        let errorStruct = ErrorContext(otel: mockSpanData)
        let dictionary = errorStruct.getDictionary()

        // Crash path still emits arch and baseAddress at the top level
        XCTAssertEqual("arm64", dictionary[Keys.arch.rawValue] as? String)
        XCTAssertEqual("0x1000000", dictionary[Keys.baseAddress.rawValue] as? String)
        // And does NOT emit buildId / stackTraceType (they were never set)
        XCTAssertNil(dictionary[Keys.buildId.rawValue])
        XCTAssertNil(dictionary[Keys.stackTraceType.rawValue])
    }

    func testGetDictionaryWithoutStackTrace() {
        mockSpanData = MockSpanData(attributes: [
            Keys.domain.rawValue: AttributeValue("com.example.error"),
            Keys.code.rawValue: AttributeValue("404"),
            Keys.errorMessage.rawValue: AttributeValue("Not Found"),
            Keys.userInfo.rawValue: AttributeValue("{\"exampleKey\": \"exampleValue\"}"),
        ])
        
        let errorStruct = ErrorContext(otel: mockSpanData)
        let dictionary = errorStruct.getDictionary()
        
        XCTAssertEqual(dictionary[Keys.domain.rawValue] as? String, "com.example.error")
        XCTAssertEqual(dictionary[Keys.userInfo.rawValue] as? [String: String], ["exampleKey": "exampleValue"])
    }
}
