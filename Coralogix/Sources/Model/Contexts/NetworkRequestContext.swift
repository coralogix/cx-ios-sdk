//
//  NetworkRequestContext.swift
//
//  Created by Coralogix DEV TEAM on 01/04/2024.
//

import Foundation
import CoralogixInternal
import WebKit

struct NetworkRequestContext {
    let method: String
    var statusCode: Int = 0
    let url: String
    let fragments: String
    let host: String
    var schema: String
    let duration: UInt64
    var responseContentLength: Int = 0
    let statusText: String

    // MARK: - Network capture rule fields (omitted from payload when nil)

    /// Maximum number of Swift `Character`s retained in `requestPayload` / `responsePayload`.
    /// The backend contract is defined in characters (matching browser SDK behaviour); if it
    /// ever changes to bytes, replace `String.prefix` with a UTF-8 byte-count truncation.
    ///
    /// NOTE: Swift's `didSet` is NOT triggered during `init`, so truncation is only enforced
    /// on post-init mutations. Any future `init` overload that sets these properties directly
    /// must call `truncatePayload(_:)` explicitly.
    private static let payloadMaxLength = 1024

    /// Allowlisted request headers captured by a matching `NetworkCaptureRule`.
    var requestHeaders: [String: String]?
    /// Allowlisted response headers captured by a matching `NetworkCaptureRule`.
    var responseHeaders: [String: String]?
    /// Stringified request body, truncated to `payloadMaxLength` characters if longer. `nil` when unavailable.
    var requestPayload: String? {
        didSet { requestPayload = Self.truncatePayload(requestPayload) }
    }
    /// Stringified response body, truncated to `payloadMaxLength` characters if longer. `nil` when unavailable or content-type unsupported.
    var responsePayload: String? {
        didSet { responsePayload = Self.truncatePayload(responsePayload) }
    }

    private static func truncatePayload(_ payload: String?) -> String? {
        payload.map { String($0.prefix(payloadMaxLength)) }
    }
    
    init(otel: SpanDataProtocol) {
        self.method = otel.getAttribute(forKey: SemanticAttributes.httpMethod.rawValue) as? String ?? Keys.undefined.rawValue
        
        if let statusCode = otel.getAttribute(forKey: SemanticAttributes.httpStatusCode.rawValue) as? String {
            self.statusCode = Int(statusCode) ?? 0
        }
        
        self.url = otel.getAttribute(forKey: SemanticAttributes.httpUrl.rawValue) as? String ?? Keys.undefined.rawValue
        
        self.fragments = otel.getAttribute(forKey: SemanticAttributes.httpTarget.rawValue) as? String ?? Keys.undefined.rawValue
        
        self.host = otel.getAttribute(forKey: SemanticAttributes.netPeerName.rawValue) as? String ?? Keys.undefined.rawValue
        
        self.schema = otel.getAttribute(forKey: SemanticAttributes.httpScheme.rawValue) as? String ?? Keys.undefined.rawValue
        
        if let startTime = otel.getStartTime(),
           let endTime = otel.getEndTime() {
            let delta = endTime - startTime
            self.duration = Global.durationToMilliseconds(duration: delta.openTelemetryFormat)
        } else {
            self.duration = 0
        }
        
        if let httpResponseBodySize = otel.getAttribute(forKey: SemanticAttributes.httpResponseBodySize.rawValue) as? String {
            self.responseContentLength = Int(httpResponseBodySize) ?? 0
        }
        
        self.statusText = otel.getStatusText()
    }
    
    func getDictionary() -> [String: Any] {
        var dict = [String: Any]()
        dict[Keys.method.rawValue]                = method
        dict[Keys.statusCode.rawValue]            = statusCode
        dict[Keys.statusText.rawValue]            = statusText
        dict[Keys.url.rawValue]                   = url
        dict[Keys.fragments.rawValue]             = fragments
        dict[Keys.host.rawValue]                  = host
        dict[Keys.schema.rawValue]                = schema
        dict[Keys.duration.rawValue]              = duration
        dict[Keys.responseContentLength.rawValue] = responseContentLength
        // Capture-rule fields: included only when set, never serialised as null.
        if let v = requestHeaders  { dict[Keys.requestHeaders.rawValue]  = v }
        if let v = responseHeaders { dict[Keys.responseHeaders.rawValue] = v }
        if let v = requestPayload  { dict[Keys.requestPayload.rawValue]  = v }
        if let v = responsePayload { dict[Keys.responsePayload.rawValue] = v }
        return dict
    }
}
