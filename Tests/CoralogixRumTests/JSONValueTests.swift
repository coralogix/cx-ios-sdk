//
//  JSONValueTests.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import XCTest
@testable import Coralogix

final class JSONValueTests: XCTestCase {

    // MARK: - Codable round-trip (lossless cases)

    func testRoundTrip_null() throws {
        try assertRoundTrip(.null)
    }

    func testRoundTrip_bool() throws {
        try assertRoundTrip(.bool(true))
        try assertRoundTrip(.bool(false))
    }

    func testRoundTrip_int() throws {
        try assertRoundTrip(.int(0))
        try assertRoundTrip(.int(42))
        try assertRoundTrip(.int(-17))
        try assertRoundTrip(.int(Int.max))
        try assertRoundTrip(.int(Int.min))
    }

    // Whole-number Doubles are lossy through JSON (see JSONValue type comment);
    // only fractional doubles round-trip exactly. The lossy case is asserted
    // separately below.
    func testRoundTrip_fractionalDouble() throws {
        try assertRoundTrip(.double(2.5))
        try assertRoundTrip(.double(-3.14159))
        try assertRoundTrip(.double(0.1))
    }

    func testRoundTrip_string() throws {
        try assertRoundTrip(.string(""))
        try assertRoundTrip(.string("hello"))
        try assertRoundTrip(.string("emoji 🎉 + unicode ñ"))
    }

    func testRoundTrip_array() throws {
        try assertRoundTrip(.array([]))
        try assertRoundTrip(.array([.int(1), .string("two"), .bool(true), .null]))
    }

    func testRoundTrip_object() throws {
        try assertRoundTrip(.object([:]))
        try assertRoundTrip(.object([
            "count":   .int(2),
            "label":   .string("auth"),
            "enabled": .bool(true),
            "ratio":   .double(0.75),
            "missing": .null,
        ]))
    }

    func testRoundTrip_nested() throws {
        try assertRoundTrip(.object([
            "user": .object([
                "id":   .int(7),
                "tags": .array([.string("admin"), .string("beta")]),
            ]),
            "scores": .array([.double(1.5), .double(2.5), .double(3.5)]),
        ]))
    }

    // MARK: - Documented caveat: whole-number Double demotes to Int

    // `.double(2.0)` encodes as JSON `2`, which decodes as `.int(2)`. This
    // test locks in that behaviour so a future "Double first on decode"
    // change can't silently flip every integer to Double — the type comment
    // on `JSONValue` explains why `Int`-first is intentional.
    func testWholeNumberDoubleDecodesAsInt() throws {
        let encoded = try JSONEncoder().encode(JSONValue.double(2.0))
        let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)
        XCTAssertEqual(decoded, .int(2))
    }

    // MARK: - toAny() shape

    func testToAny_primitives() {
        XCTAssertTrue(JSONValue.null.toAny() is NSNull)
        XCTAssertEqual(JSONValue.bool(true).toAny() as? Bool,       true)
        XCTAssertEqual(JSONValue.int(7).toAny() as? Int,            7)
        XCTAssertEqual(JSONValue.double(1.5).toAny() as? Double,    1.5)
        XCTAssertEqual(JSONValue.string("hi").toAny() as? String,   "hi")
    }

    func testToAny_nestedIsJSONSerializationCompatible() throws {
        let value: JSONValue = .object([
            "list": .array([.int(1), .string("two")]),
            "flag": .bool(false),
        ])
        let any = value.toAny()
        XCTAssertTrue(JSONSerialization.isValidJSONObject(any))
        // Spot-check the nested shape made the trip into Foundation types.
        let dict = try XCTUnwrap(any as? [String: Any])
        let list = try XCTUnwrap(dict["list"] as? [Any])
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0] as? Int, 1)
        XCTAssertEqual(list[1] as? String, "two")
        XCTAssertEqual(dict["flag"] as? Bool, false)
    }

    // MARK: - Helpers

    private func assertRoundTrip(_ value: JSONValue,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) throws {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }
}
