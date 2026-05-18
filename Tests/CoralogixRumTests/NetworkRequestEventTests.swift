//
//  NetworkRequestEventTests.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class NetworkRequestEventTests: XCTestCase {

    func testEventTypeIsNetworkRequest() {
        let event = makeEvent()
        XCTAssertEqual(event.type, CoralogixEventType.networkRequest)
        XCTAssertEqual(event.type.rawValue, "network-request")
    }

    func testAdapterEmitsRequiredHttpAttributes() {
        let event = makeEvent()
        let attrs = event.toOTelAttributes()

        XCTAssertEqual(attrs[Keys.eventType.rawValue],                        .string("network-request"))
        XCTAssertEqual(attrs[SemanticAttributes.httpMethod.rawValue],         .string("GET"))
        XCTAssertEqual(attrs[SemanticAttributes.httpUrl.rawValue],            .string("https://api.example.com/v1/foo?x=1"))
        XCTAssertEqual(attrs[SemanticAttributes.httpTarget.rawValue],         .string("/v1/foo"))
        XCTAssertEqual(attrs[SemanticAttributes.netPeerName.rawValue],        .string("api.example.com"))
        XCTAssertEqual(attrs[SemanticAttributes.httpScheme.rawValue],         .string("https"))
        XCTAssertEqual(attrs[SemanticAttributes.httpStatusCode.rawValue],     .int(200))
        XCTAssertEqual(attrs[SemanticAttributes.httpResponseBodySize.rawValue], .int(1234))
    }

    // Adapter intentionally omits duration/statusText — they reach the wire
    // via span timing and span status, not OTel attributes.
    func testAdapterOmitsDurationAndStatusText() {
        let event = makeEvent(duration: 9999, statusText: "OK")
        let attrs = event.toOTelAttributes()

        XCTAssertNil(attrs[Keys.duration.rawValue])
        XCTAssertNil(attrs[Keys.statusText.rawValue])
    }

    func testAdapterOmitsUnsetCaptureRuleFields() {
        let attrs = makeEvent().toOTelAttributes()
        XCTAssertNil(attrs[Keys.requestHeaders.rawValue])
        XCTAssertNil(attrs[Keys.responseHeaders.rawValue])
        XCTAssertNil(attrs[Keys.requestPayload.rawValue])
        XCTAssertNil(attrs[Keys.responsePayload.rawValue])
    }

    func testAdapterEmitsHeadersAsJsonStringWhenSet() throws {
        let event = makeEvent(
            requestHeaders: ["Content-Type": "application/json"],
            responseHeaders: ["X-Trace-Id": "abc"]
        )
        let attrs = event.toOTelAttributes()

        let reqJson = try XCTUnwrap(extractString(attrs[Keys.requestHeaders.rawValue]))
        let resJson = try XCTUnwrap(extractString(attrs[Keys.responseHeaders.rawValue]))

        let reqDict = try XCTUnwrap(Helper.convertJsonStringToDict(jsonString: reqJson))
        XCTAssertEqual(reqDict["Content-Type"] as? String, "application/json")

        let resDict = try XCTUnwrap(Helper.convertJsonStringToDict(jsonString: resJson))
        XCTAssertEqual(resDict["X-Trace-Id"] as? String, "abc")
    }

    // Parity: pipe a fully-populated event through the existing exporter path
    // (NetworkRequestContext.init(otel:) -> getDictionary()) and assert every
    // wire-dict field matches the original.
    func testDictParityViaExistingContextPath_fullPopulation() throws {
        let event = makeEvent(
            duration: 250,                       // expected wire value
            statusText: "undefined",             // SpanDataExt always returns "undefined"
            requestHeaders: ["Authorization": "Bearer xyz"],
            responseHeaders: ["Server": "nginx"],
            requestPayload: #"{"q":"hello"}"#,
            responsePayload: #"{"ok":true}"#
        )

        // 250ms duration: start=0, end=0.250s
        let mockSpan = MockSpanData(
            attributes: event.toOTelAttributes(),
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 0.250)
        )
        let context = NetworkRequestContext(otel: mockSpan)
        let dict = context.getDictionary()

        XCTAssertEqual(dict[Keys.method.rawValue]                as? String, "GET")
        XCTAssertEqual(dict[Keys.statusCode.rawValue]            as? Int,    200)
        XCTAssertEqual(dict[Keys.url.rawValue]                   as? String, "https://api.example.com/v1/foo?x=1")
        XCTAssertEqual(dict[Keys.fragments.rawValue]             as? String, "/v1/foo")
        XCTAssertEqual(dict[Keys.host.rawValue]                  as? String, "api.example.com")
        XCTAssertEqual(dict[Keys.schema.rawValue]                as? String, "https")
        XCTAssertEqual(dict[Keys.duration.rawValue]              as? UInt64, 250)
        XCTAssertEqual(dict[Keys.responseContentLength.rawValue] as? Int,    1234)
        XCTAssertEqual(dict[Keys.statusText.rawValue]            as? String, Keys.undefined.rawValue)

        let reqHeaders = try XCTUnwrap(dict[Keys.requestHeaders.rawValue] as? [String: String])
        XCTAssertEqual(reqHeaders["Authorization"], "Bearer xyz")

        let resHeaders = try XCTUnwrap(dict[Keys.responseHeaders.rawValue] as? [String: String])
        XCTAssertEqual(resHeaders["Server"], "nginx")

        XCTAssertEqual(dict[Keys.requestPayload.rawValue]  as? String, #"{"q":"hello"}"#)
        XCTAssertEqual(dict[Keys.responsePayload.rawValue] as? String, #"{"ok":true}"#)
    }

    func testCodableRoundTrip() throws {
        let original = makeEvent(
            requestHeaders: ["A": "1"],
            responseHeaders: ["B": "2"],
            requestPayload: "req",
            responsePayload: "res"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetworkRequestEvent.self, from: encoded)

        XCTAssertEqual(decoded.id,                    original.id)
        XCTAssertEqual(decoded.type,                  original.type)
        XCTAssertEqual(decoded.method,                original.method)
        XCTAssertEqual(decoded.statusCode,            original.statusCode)
        XCTAssertEqual(decoded.url,                   original.url)
        XCTAssertEqual(decoded.fragments,             original.fragments)
        XCTAssertEqual(decoded.host,                  original.host)
        XCTAssertEqual(decoded.schema,                original.schema)
        XCTAssertEqual(decoded.duration,              original.duration)
        XCTAssertEqual(decoded.statusText,            original.statusText)
        XCTAssertEqual(decoded.responseContentLength, original.responseContentLength)
        XCTAssertEqual(decoded.requestHeaders,        original.requestHeaders)
        XCTAssertEqual(decoded.responseHeaders,       original.responseHeaders)
        XCTAssertEqual(decoded.requestPayload,        original.requestPayload)
        XCTAssertEqual(decoded.responsePayload,       original.responsePayload)
    }

    // MARK: - Helpers

    private func makeEvent(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        method: String = "GET",
        statusCode: Int = 200,
        url: String = "https://api.example.com/v1/foo?x=1",
        fragments: String = "/v1/foo",
        host: String = "api.example.com",
        schema: String = "https",
        duration: UInt64 = 0,
        statusText: String = "",
        responseContentLength: Int = 1234,
        requestHeaders: [String: String]? = nil,
        responseHeaders: [String: String]? = nil,
        requestPayload: String? = nil,
        responsePayload: String? = nil
    ) -> NetworkRequestEvent {
        return NetworkRequestEvent(
            id: id,
            timestamp: timestamp,
            method: method,
            statusCode: statusCode,
            url: url,
            fragments: fragments,
            host: host,
            schema: schema,
            duration: duration,
            statusText: statusText,
            responseContentLength: responseContentLength,
            requestHeaders: requestHeaders,
            responseHeaders: responseHeaders,
            requestPayload: requestPayload,
            responsePayload: responsePayload
        )
    }

    private func extractString(_ value: AttributeValue?) -> String? {
        guard case let .string(s) = value else { return nil }
        return s
    }
}
