//
//  ViewLifecycleEventTests.swift
//
//
//  Created by Coralogix DEV TEAM on 17/05/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class ViewLifecycleEventTests: XCTestCase {

    func testEventTypeAliasMatchesCoralogixEventType() {
        XCTAssertEqual(EventType.lifeCycle, CoralogixEventType.lifeCycle)
        XCTAssertEqual(EventType.lifeCycle.rawValue, "life-cycle")
    }

    func testAdapterEmitsEventTypeDiscriminator() {
        let event = ViewLifecycleEvent(lifeCycleType: Keys.appDidFinishLaunching.rawValue)
        let attrs = event.toOTelAttributes()

        XCTAssertEqual(
            attrs[Keys.eventType.rawValue],
            .string(CoralogixEventType.lifeCycle.rawValue)
        )
    }

    func testAdapterEmitsLifeCycleTypeUnderKeysType() {
        let event = ViewLifecycleEvent(lifeCycleType: Keys.appDidFinishLaunching.rawValue)
        let attrs = event.toOTelAttributes()

        XCTAssertEqual(
            attrs[Keys.type.rawValue],
            .string(Keys.appDidFinishLaunching.rawValue)
        )
    }

    // Parity: feed the adapter output through the existing exporter path
    // (LifeCycleContext.init(otel:) -> getLifeCycleDictionary()) and assert
    // the wire dict matches what today's flow produces.
    func testDictParityViaExistingContextPath() {
        let event = ViewLifecycleEvent(
            lifeCycleType: Keys.appDidBecomeActiveNotification.rawValue
        )

        let mockSpan = MockSpanData(attributes: event.toOTelAttributes())
        let context = LifeCycleContext(otel: mockSpan)
        let dict = context.getLifeCycleDictionary()

        XCTAssertEqual(
            dict[Keys.eventName.rawValue] as? String,
            Keys.appDidBecomeActiveNotification.rawValue
        )
        XCTAssertEqual(dict.count, 1, "life_cycle_context should contain only event_name")
    }

    func testCodableRoundTrip() throws {
        let original = ViewLifecycleEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            lifeCycleType: Keys.appDidEnterBackgroundNotification.rawValue
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ViewLifecycleEvent.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.lifeCycleType, original.lifeCycleType)
    }
}
