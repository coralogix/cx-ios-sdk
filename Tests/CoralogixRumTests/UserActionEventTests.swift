//
//  UserActionEventTests.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class UserActionEventTests: XCTestCase {

    func testEventTypeIsUserInteraction() {
        let event = UserActionEvent(eventName: .click, targetElement: "button")
        XCTAssertEqual(event.type, CoralogixEventType.userInteraction)
        XCTAssertEqual(event.type.rawValue, "user-interaction")
    }

    func testAdapterEmitsEventTypeDiscriminator() {
        let event = UserActionEvent(eventName: .click, targetElement: "button")
        let attrs = event.toOTelAttributes()

        XCTAssertEqual(
            attrs[Keys.eventType.rawValue],
            .string(CoralogixEventType.userInteraction.rawValue)
        )
    }

    func testAdapterEmitsTapObjectAsJsonString() throws {
        let event = UserActionEvent(eventName: .click, targetElement: "loginButton")
        let attrs = event.toOTelAttributes()

        let tapJson = try XCTUnwrap(
            extractString(attrs[Keys.tapObject.rawValue]),
            "tap_object attribute should be a JSON string"
        )

        let parsed = try XCTUnwrap(
            Helper.convertJsonStringToDict(jsonString: tapJson)
        )
        XCTAssertEqual(parsed[Keys.eventName.rawValue] as? String, "click")
        XCTAssertEqual(parsed[Keys.targetElement.rawValue] as? String, "loginButton")
    }

    // Parity: feed the adapter output through the existing exporter path
    // (InteractionContext.init(otel:) -> getDictionary()) and assert the
    // resulting wire dict matches the original field set.
    func testDictParityViaExistingContextPath_clickWithAllOptionals() {
        let event = UserActionEvent(
            eventName: .click,
            targetElement: "loginButton",
            elementClasses: "UIButton",
            elementId: "login",
            targetElementInnerText: "Sign in"
        )

        let mockSpan = MockSpanData(attributes: event.toOTelAttributes())
        let context = InteractionContext(otel: mockSpan)
        let dict = context.getDictionary()

        XCTAssertEqual(dict[Keys.eventName.rawValue] as? String, "click")
        XCTAssertEqual(dict[Keys.targetElement.rawValue] as? String, "loginButton")
        XCTAssertEqual(dict[Keys.elementClasses.rawValue] as? String, "UIButton")
        XCTAssertEqual(dict[Keys.elementId.rawValue] as? String, "login")
        XCTAssertEqual(dict[Keys.targetElementInnerText.rawValue] as? String, "Sign in")
        XCTAssertNil(dict[Keys.scrollDirection.rawValue])
        XCTAssertNil(dict[Keys.attributes.rawValue])
    }

    func testDictParityViaExistingContextPath_clickWithAttributes() throws {
        let event = UserActionEvent(
            eventName: .click,
            targetElement: "loginButton",
            attributes: [
                "loginMethod": .string("oauth"),
                "retryCount":  .int(2),
                "rememberMe":  .bool(true),
                "tags":        .array([.string("urgent"), .string("auth")])
            ]
        )

        let mockSpan = MockSpanData(attributes: event.toOTelAttributes())
        let context = InteractionContext(otel: mockSpan)
        let dict = context.getDictionary()

        let attrs = try XCTUnwrap(dict[Keys.attributes.rawValue] as? [String: Any])
        XCTAssertEqual(attrs["loginMethod"] as? String, "oauth")
        XCTAssertEqual(attrs["retryCount"]  as? Int,    2)
        XCTAssertEqual(attrs["rememberMe"]  as? Bool,   true)
        XCTAssertEqual(attrs["tags"] as? [String], ["urgent", "auth"])
    }

    func testDictParityViaExistingContextPath_scrollWithDirection() {
        let event = UserActionEvent(
            eventName: .scroll,
            targetElement: "feedList",
            scrollDirection: .down
        )

        let mockSpan = MockSpanData(attributes: event.toOTelAttributes())
        let context = InteractionContext(otel: mockSpan)
        let dict = context.getDictionary()

        XCTAssertEqual(dict[Keys.eventName.rawValue] as? String, "scroll")
        XCTAssertEqual(dict[Keys.targetElement.rawValue] as? String, "feedList")
        XCTAssertEqual(dict[Keys.scrollDirection.rawValue] as? String, "down")
    }

    func testCodableRoundTrip() throws {
        let original = UserActionEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            eventName: .scroll,
            targetElement: "feedList",
            elementClasses: "UICollectionView",
            elementId: "feed",
            targetElementInnerText: nil,
            scrollDirection: .up
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserActionEvent.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.eventName, original.eventName)
        XCTAssertEqual(decoded.targetElement, original.targetElement)
        XCTAssertEqual(decoded.elementClasses, original.elementClasses)
        XCTAssertEqual(decoded.elementId, original.elementId)
        XCTAssertNil(decoded.targetElementInnerText)
        XCTAssertEqual(decoded.scrollDirection, original.scrollDirection)
    }

    // MARK: - Helpers

    private func extractString(_ value: AttributeValue?) -> String? {
        guard case let .string(s) = value else { return nil }
        return s
    }
}
