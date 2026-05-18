//
//  ErrorEventTests.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class ErrorEventTests: XCTestCase {

    func testEventTypeIsError() {
        let event = ErrorEvent(domain: "NSURLErrorDomain", errorMessage: "boom")
        XCTAssertEqual(event.type, CoralogixEventType.error)
        XCTAssertEqual(event.type.rawValue, "error")
    }

    func testAdapterAlwaysEmitsRequiredFields() {
        let event = ErrorEvent(domain: "io.app.network", errorMessage: "no internet")
        let attrs = event.toOTelAttributes()

        XCTAssertEqual(attrs[Keys.eventType.rawValue],    .string("error"))
        XCTAssertEqual(attrs[Keys.domain.rawValue],       .string("io.app.network"))
        XCTAssertEqual(attrs[Keys.errorMessage.rawValue], .string("no internet"))
        XCTAssertEqual(attrs[Keys.isCrash.rawValue],      .bool(false))
    }

    func testAdapterOmitsUnsetOptionals() {
        let event = ErrorEvent(domain: "d", errorMessage: "m")
        let attrs = event.toOTelAttributes()

        XCTAssertNil(attrs[Keys.code.rawValue])
        XCTAssertNil(attrs[Keys.errorType.rawValue])
        XCTAssertNil(attrs[Keys.arch.rawValue])
        XCTAssertNil(attrs[Keys.buildId.rawValue])
        XCTAssertNil(attrs[Keys.stackTraceType.rawValue])
        XCTAssertNil(attrs[Keys.userInfo.rawValue])
        XCTAssertNil(attrs[Keys.stackTrace.rawValue])
    }

    func testAdapterEmitsCodeAsInt() {
        let event = ErrorEvent(domain: "d", code: 404, errorMessage: "m")
        XCTAssertEqual(event.toOTelAttributes()[Keys.code.rawValue], .int(404))
    }

    // Parity: pipe a fully-populated event through the existing exporter path
    // (ErrorContext.init(otel:) -> getDictionary()) and assert the resulting
    // wire dict matches the original field set.
    func testDictParityViaExistingContextPath_fullPopulation() throws {
        let userInfoJson = Helper.convertDictionaryToJsonString(dict: [
            "reason": "timeout",
            "retry": 3
        ])
        let stackFrames: [[String: Any]] = [
            ["function": "main", "file": "AppDelegate.swift", "line": 12]
        ]
        let stackJson = try String(
            data: JSONSerialization.data(withJSONObject: stackFrames, options: []),
            encoding: .utf8
        ) ?? "[]"

        let event = ErrorEvent(
            domain: "io.app.network",
            code: 504,
            errorMessage: "gateway timeout",
            isCrash: false,
            errorType: "HTTPError",
            arch: "arm64",
            buildId: "abc123",
            stackTraceType: "swift",
            userInfoJson: userInfoJson,
            stackTraceJson: stackJson
        )

        let mockSpan = MockSpanData(attributes: event.toOTelAttributes())
        let context = ErrorContext(otel: mockSpan)
        let dict = context.getDictionary()

        XCTAssertEqual(dict[Keys.domain.rawValue]         as? String, "io.app.network")
        XCTAssertEqual(dict[Keys.code.rawValue]           as? String, "504")
        XCTAssertEqual(dict[Keys.errorMessage.rawValue]   as? String, "gateway timeout")
        XCTAssertEqual(dict[Keys.errorType.rawValue]      as? String, "HTTPError")
        XCTAssertEqual(dict[Keys.arch.rawValue]           as? String, "arm64")
        XCTAssertEqual(dict[Keys.buildId.rawValue]        as? String, "abc123")
        XCTAssertEqual(dict[Keys.stackTraceType.rawValue] as? String, "swift")
        XCTAssertEqual(dict[Keys.isCrash.rawValue]        as? Bool,   false)

        let userInfoDict = try XCTUnwrap(dict[Keys.userInfo.rawValue] as? [String: Any])
        XCTAssertEqual(userInfoDict["reason"] as? String, "timeout")
        XCTAssertEqual(userInfoDict["retry"]  as? Int,    3)

        // ErrorContext renames stack_trace -> original_stacktrace on the way out.
        let stack = try XCTUnwrap(dict[Keys.originalStackTrace.rawValue] as? [[String: Any]])
        XCTAssertEqual(stack.first?["function"] as? String, "main")
    }

    func testCodableRoundTrip() throws {
        let original = ErrorEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            domain: "d",
            code: 42,
            errorMessage: "m",
            isCrash: true,
            errorType: "Crash",
            arch: "arm64",
            buildId: nil,
            stackTraceType: "objc",
            userInfoJson: nil,
            stackTraceJson: "[]"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ErrorEvent.self, from: encoded)

        XCTAssertEqual(decoded.id,             original.id)
        XCTAssertEqual(decoded.timestamp,      original.timestamp)
        XCTAssertEqual(decoded.type,           original.type)
        XCTAssertEqual(decoded.domain,         original.domain)
        XCTAssertEqual(decoded.code,           original.code)
        XCTAssertEqual(decoded.errorMessage,   original.errorMessage)
        XCTAssertEqual(decoded.isCrash,        original.isCrash)
        XCTAssertEqual(decoded.errorType,      original.errorType)
        XCTAssertEqual(decoded.arch,           original.arch)
        XCTAssertNil(decoded.buildId)
        XCTAssertEqual(decoded.stackTraceType, original.stackTraceType)
        XCTAssertNil(decoded.userInfoJson)
        XCTAssertEqual(decoded.stackTraceJson, original.stackTraceJson)
    }
}
