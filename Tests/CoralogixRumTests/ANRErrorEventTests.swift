//
//  ANRErrorEventTests.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class ANRErrorEventTests: XCTestCase {

    func testEventTypeIsError() {
        let event = ANRErrorEvent()
        XCTAssertEqual(event.type, CoralogixEventType.error)
        XCTAssertEqual(event.type.rawValue, "error")
    }

    func testDefaultsMatchExistingANRPath() {
        let event = ANRErrorEvent()
        XCTAssertEqual(event.errorMessage, "Application Not Responding for at least 1000 ms.")
        XCTAssertEqual(event.errorType, "ANR")
    }

    func testAdapterEmitsRequiredAttributes() {
        let event = ANRErrorEvent()
        let attrs = event.toOTelAttributes()

        XCTAssertEqual(attrs[Keys.eventType.rawValue],    .string("error"))
        XCTAssertEqual(attrs[Keys.errorMessage.rawValue], .string("Application Not Responding for at least 1000 ms."))
        XCTAssertEqual(attrs[Keys.errorType.rawValue],    .string("ANR"))
        XCTAssertEqual(attrs.count, 3)
    }

    // Parity: feed the adapter output through the existing exporter path
    // (ErrorContext.init(otel:) -> getDictionary()) and assert the wire dict
    // matches what the current ANR flow produces.
    func testDictParityViaExistingContextPath() {
        let event = ANRErrorEvent()

        let mockSpan = MockSpanData(attributes: event.toOTelAttributes())
        let context = ErrorContext(otel: mockSpan)
        let dict = context.getDictionary()

        XCTAssertEqual(dict[Keys.errorMessage.rawValue] as? String, "Application Not Responding for at least 1000 ms.")
        XCTAssertEqual(dict[Keys.errorType.rawValue]    as? String, "ANR")
        XCTAssertEqual(dict[Keys.isCrash.rawValue]      as? Bool,   false)
        // Optional/empty fields should NOT appear on the wire.
        XCTAssertNil(dict[Keys.domain.rawValue])
        XCTAssertNil(dict[Keys.code.rawValue])
        XCTAssertNil(dict[Keys.userInfo.rawValue])
        XCTAssertNil(dict[Keys.originalStackTrace.rawValue])
        XCTAssertNil(dict[Keys.arch.rawValue])
        XCTAssertNil(dict[Keys.buildId.rawValue])
        XCTAssertNil(dict[Keys.stackTraceType.rawValue])
    }

    /// The threads go on the wire as a crash's do, and the ANR stays a non-crash error.
    func testThreads_reachTheWire_withIsCrashFalse() throws {
        let threads = #"["[{\"frameNumber\":\"0\"}]","[{\"frameNumber\":\"0\"},{\"frameNumber\":\"1\"}]"]"#
        let event = ANRErrorEvent(threads: threads)
        XCTAssertEqual(event.toOTelAttributes()[Keys.threads.rawValue], .string(threads))

        let dict = ErrorContext(otel: MockSpanData(attributes: event.toOTelAttributes())).getDictionary()

        let sent = try XCTUnwrap(dict[Keys.threads.rawValue] as? [[[String: Any]]])
        XCTAssertEqual(sent.map(\.count), [1, 2])
        XCTAssertEqual(dict[Keys.isCrash.rawValue] as? Bool, false)
        XCTAssertEqual(dict[Keys.errorType.rawValue] as? String, "ANR")
    }

    func testCodableRoundTrip() throws {
        let original = ANRErrorEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            errorMessage: "Hang detected",
            errorType: "ANR"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ANRErrorEvent.self, from: encoded)

        XCTAssertEqual(decoded.id,           original.id)
        XCTAssertEqual(decoded.timestamp,    original.timestamp)
        XCTAssertEqual(decoded.type,         original.type)
        XCTAssertEqual(decoded.errorMessage, original.errorMessage)
        XCTAssertEqual(decoded.errorType,    original.errorType)
    }
}
