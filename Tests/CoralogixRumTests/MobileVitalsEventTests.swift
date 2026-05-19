//
//  MobileVitalsEventTests.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class MobileVitalsEventTests: XCTestCase {

    func testEventTypeIsMobileVitals() {
        let event = MobileVitalsEvent(mobileVitalsType: "{}")
        XCTAssertEqual(event.type, CoralogixEventType.mobileVitals)
        XCTAssertEqual(event.type.rawValue, "mobile-vitals")
    }

    func testAdapterEmitsEventTypeDiscriminator() {
        let event = MobileVitalsEvent(mobileVitalsType: "{}")
        let attrs = event.toOTelAttributes()

        XCTAssertEqual(
            attrs[Keys.eventType.rawValue],
            .string(CoralogixEventType.mobileVitals.rawValue)
        )
    }

    func testAdapterEmitsPayloadUnderKeysMobileVitalsType() {
        let payload = Helper.convertDictionaryToJsonString(dict: [
            "fps": [Keys.mobileVitalsUnits.rawValue: "fps", Keys.value.rawValue: 60]
        ])
        let event = MobileVitalsEvent(mobileVitalsType: payload)
        let attrs = event.toOTelAttributes()

        XCTAssertEqual(
            attrs[Keys.mobileVitalsType.rawValue],
            .string(payload)
        )
    }

    // Parity: feed the adapter output through the existing exporter path
    // (MobileVitalsContext.init(otel:) -> getMobileVitalsDictionary()) and
    // assert the resulting wire dict matches the original payload bit-for-bit.
    func testDictParityViaExistingContextPath() throws {
        let originalDict: [String: Any] = [
            "fps": [
                Keys.mobileVitalsUnits.rawValue: "fps",
                Keys.value.rawValue: 60
            ]
        ]
        let payload = Helper.convertDictionaryToJsonString(dict: originalDict)
        let event = MobileVitalsEvent(mobileVitalsType: payload)

        let mockSpan = MockSpanData(attributes: event.toOTelAttributes())
        let context = MobileVitalsContext(otel: mockSpan)
        let dict = context.getMobileVitalsDictionary()

        let fps = try XCTUnwrap(dict["fps"] as? [String: Any])
        XCTAssertEqual(fps[Keys.mobileVitalsUnits.rawValue] as? String, "fps")
        XCTAssertEqual(fps[Keys.value.rawValue] as? Int, 60)
        XCTAssertEqual(dict.count, 1)
    }

    func testCodableRoundTrip() throws {
        let original = MobileVitalsEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            mobileVitalsType: #"{"cpu":{"units":"percent","value":42}}"#
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MobileVitalsEvent.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.mobileVitalsType, original.mobileVitalsType)
    }
}
