//
//  NetworkRequestEvent.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import Foundation
import CoralogixInternal

/// Logical representation of a network-request RUM event.
///
/// IMPORTANT: `toOTelAttributes()` does NOT cover the full wire shape on its
/// own. `duration` and `statusText` reach the backend via OTel span
/// **infrastructure** (start/end time, span status) — they have no OTel
/// attribute slot. Any consumer wiring a `NetworkRequestEvent` into a real
/// span emission path must, in addition to applying `toOTelAttributes()`,
/// set span timing from `duration` and span status from `statusText`.
/// Forgetting either produces wire output that silently omits the field
/// without failing tests.
struct NetworkRequestEvent: TelemetryEvent {
    let id: UUID
    let timestamp: Date
    var type: EventType { .networkRequest }
    let method: String
    let statusCode: Int
    let url: String
    let fragments: String
    let host: String
    let schema: String

    /// Span-derived. NOT emitted by `toOTelAttributes()`. The consumer must
    /// translate this into the span's `startTime` / `endTime` at emission.
    let duration: UInt64
    /// Span-derived. NOT emitted by `toOTelAttributes()`. The consumer must
    /// translate this into the span's status at emission.
    let statusText: String

    let responseContentLength: Int

    // Optional capture-rule fields (CX-33233 / CX-33234). Headers travel as
    // JSON-encoded strings on the OTel span; payloads as raw strings.
    let requestHeaders: [String: String]?
    let responseHeaders: [String: String]?
    let requestPayload: String?
    let responsePayload: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String,
        statusCode: Int = 0,
        url: String,
        fragments: String = "",
        host: String,
        schema: String,
        duration: UInt64 = 0,
        statusText: String = "",
        responseContentLength: Int = 0,
        requestHeaders: [String: String]? = nil,
        responseHeaders: [String: String]? = nil,
        requestPayload: String? = nil,
        responsePayload: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.statusCode = statusCode
        self.url = url
        self.fragments = fragments
        self.host = host
        self.schema = schema
        self.duration = duration
        self.statusText = statusText
        self.responseContentLength = responseContentLength
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.requestPayload = requestPayload
        self.responsePayload = responsePayload
    }

    func toOTelAttributes() -> [String: AttributeValue] {
        var attrs: [String: AttributeValue] = [
            Keys.eventType.rawValue:                          .string(type.rawValue),
            SemanticAttributes.httpMethod.rawValue:           .string(method),
            SemanticAttributes.httpUrl.rawValue:              .string(url),
            SemanticAttributes.httpTarget.rawValue:           .string(fragments),
            SemanticAttributes.netPeerName.rawValue:          .string(host),
            SemanticAttributes.httpScheme.rawValue:           .string(schema),
            SemanticAttributes.httpStatusCode.rawValue:       .int(statusCode),
            SemanticAttributes.httpResponseBodySize.rawValue: .int(responseContentLength),
        ]
        if let requestHeaders {
            let json = Helper.convertDictionaryToJsonString(dict: requestHeaders)
            attrs[Keys.requestHeaders.rawValue] = .string(json)
        }
        if let responseHeaders {
            let json = Helper.convertDictionaryToJsonString(dict: responseHeaders)
            attrs[Keys.responseHeaders.rawValue] = .string(json)
        }
        if let requestPayload  { attrs[Keys.requestPayload.rawValue]  = .string(requestPayload) }
        if let responsePayload { attrs[Keys.responsePayload.rawValue] = .string(responsePayload) }
        return attrs
    }
}
