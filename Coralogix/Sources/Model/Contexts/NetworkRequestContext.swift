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
    /// Hostname labels left of `domain` (e.g. "blog" for blog.example.com); empty when the
    /// hostname has no more than two labels. `nil` when `url` has no parseable host.
    let subdomain: String?
    /// Last two hostname labels (e.g. "example.com"). `nil` when `url` has no parseable host.
    let domain: String?
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
    /// Stringified response body. Never truncated: if > `payloadMaxLength` the payload is dropped (CX-33234).
    var responsePayload: String? {
        didSet { responsePayload = Self.capResponsePayload(responsePayload) }
    }

    private static func truncatePayload(_ payload: String?) -> String? {
        payload.map { String($0.prefix(payloadMaxLength)) }
    }

    /// Drops response payload when over limit (no truncation per CX-33234).
    /// Double-gate: `NetworkCaptureRule.stringifyBody` already drops payloads > 1024 chars before they
    /// reach the span; this is a safety net for direct attribute assignments.
    private static func capResponsePayload(_ payload: String?) -> String? {
        guard let p = payload, p.count <= payloadMaxLength else { return nil }
        return p
    }
    
    init(otel: SpanDataProtocol) {
        self.method = otel.getAttribute(forKey: SemanticAttributes.httpMethod.rawValue) as? String ?? Keys.undefined.rawValue
        
        if let statusCode = otel.getAttribute(forKey: SemanticAttributes.httpStatusCode.rawValue) as? String {
            self.statusCode = Int(statusCode) ?? 0
        }
        
        self.url = otel.getAttribute(forKey: SemanticAttributes.httpUrl.rawValue) as? String ?? Keys.undefined.rawValue
        
        self.fragments = otel.getAttribute(forKey: SemanticAttributes.httpTarget.rawValue) as? String ?? Keys.undefined.rawValue
        
        // Taken from the URL when it parses, so native and hybrid requests agree with the browser
        // SDK; the span attributes are the fallback.
        let urlParts = Self.urlParts(url)
        self.host = urlParts?.host
            ?? otel.getAttribute(forKey: SemanticAttributes.netPeerName.rawValue) as? String
            ?? Keys.undefined.rawValue
        
        self.schema = urlParts?.schema
            ?? otel.getAttribute(forKey: SemanticAttributes.httpScheme.rawValue) as? String
            ?? Keys.undefined.rawValue

        self.subdomain = urlParts?.subdomain
        self.domain = urlParts?.domain
        
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
        
        // Hybrid platforms report the response's reason phrase through the bridge as a span
        // attribute; the OTel span status text is not usable on iOS (getStatusText is stubbed
        // around an upstream bug), so the attribute wins. Native spans never set the attribute
        // and keep their existing value.
        if let hybridStatusText = otel.getAttribute(forKey: Keys.statusText.rawValue) as? String,
           !hybridStatusText.isEmpty {
            self.statusText = hybridStatusText
        } else {
            self.statusText = otel.getStatusText()
        }

        // Network capture: allowlisted headers (CX-33233) stored as JSON on the span
        if let raw = otel.getAttribute(forKey: Keys.requestHeaders.rawValue) as? String,
           let dict = Helper.convertJsonStringToDict(jsonString: raw) {
            self.requestHeaders = dict.mapValues { $0 as? String ?? String(describing: $0) }
        }
        if let raw = otel.getAttribute(forKey: Keys.responseHeaders.rawValue) as? String,
           let dict = Helper.convertJsonStringToDict(jsonString: raw) {
            self.responseHeaders = dict.mapValues { $0 as? String ?? String(describing: $0) }
        }
        // Network capture: payloads set on span by receivedResponse (CX-33233/CX-33234).
        // Truncation/cap applied here explicitly; didSet is not run during init.
        self.requestPayload = Self.truncatePayload(otel.getAttribute(forKey: Keys.requestPayload.rawValue) as? String)
        self.responsePayload = Self.capResponsePayload(otel.getAttribute(forKey: Keys.responsePayload.rawValue) as? String)
    }
    
    /// Labels that make up the registrable domain (e.g. "example.com"); everything to the left is
    /// the subdomain. Naive last-two-labels split matching the browser SDK — multi-part TLDs
    /// (e.g. "co.uk") are a known limitation.
    private static let registrableDomainLabelCount = 2

    /// Ports the browser's `URL.host` omits for their scheme.
    private static let defaultPorts = ["http": 80, "https": 443, "ws": 80, "wss": 443]

    /// Characters left as-is when re-encoding a URL that failed to parse: everything valid in a
    /// query, plus the delimiters and escapes a URL may already contain.
    private static let urlRetryAllowedCharacters = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "#[]%"))

    /// Extracts the URL parts the browser SDK reports, with the same meaning:
    /// - `schema`: the lowercased scheme, e.g. "https".
    /// - `host`: the hostname plus `:port` when the URL names a non-default port, like the
    ///   browser's `URL.host` ("api.example.com:8443", but "api.example.com" for "https://...:443").
    /// - `subdomain` / `domain`: see `splitHostname`.
    /// `nil` when `url` has no parseable host.
    ///
    /// Known differences from the browser: long-form IPv6 hosts are not shortened, and
    /// internationalised hosts are reported as Unicode rather than punycode.
    static func urlParts(_ url: String) -> (schema: String, host: String, subdomain: String, domain: String)? {
        guard let parsed = parseURL(url),
              let scheme = parsed.scheme?.lowercased(),
              let hostname = parsed.host?.lowercased(),
              !hostname.isEmpty else { return nil }
        // Foundation strips the brackets from IPv6 literals; the browser keeps them in both
        // `host` and `hostname`, so the subdomain/domain split runs on the bracketed form too.
        let bracketedHost = hostname.contains(":") ? "[\(hostname)]" : hostname
        let hostnameParts = splitHostname(bracketedHost)
        let host: String
        if let port = parsed.port, port != defaultPorts[scheme] {
            host = "\(bracketedHost):\(port)"
        } else {
            host = bracketedHost
        }
        return (schema: scheme, host: host, subdomain: hostnameParts.subdomain, domain: hostnameParts.domain)
    }

    /// Before iOS 17, `URL(string:)` rejects URLs with unencoded characters (a space in the query,
    /// `|`, ...) that the browser accepts, so retry once with those characters percent-encoded.
    /// The first attempt is strict on every OS version so all versions take the same path.
    private static func parseURL(_ url: String) -> URL? {
        let strict: URL?
        if #available(iOS 17.0, tvOS 17.0, macOS 14.0, *) {
            strict = URL(string: url, encodingInvalidCharacters: false)
        } else {
            strict = URL(string: url)
        }
        if let strict { return strict }
        return url.addingPercentEncoding(withAllowedCharacters: urlRetryAllowedCharacters).flatMap(URL.init(string:))
    }

    /// Naive last-two-labels split of an already-lowercased hostname, matching the browser SDK.
    private static func splitHostname(_ hostname: String) -> (subdomain: String, domain: String) {
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        return (
            subdomain: labels.dropLast(registrableDomainLabelCount).joined(separator: "."),
            domain: labels.suffix(registrableDomainLabelCount).joined(separator: ".")
        )
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
        if let v = subdomain { dict[Keys.subdomain.rawValue] = v }
        if let v = domain    { dict[Keys.domain.rawValue]    = v }
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
