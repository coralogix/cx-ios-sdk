//
//  NetworkCaptureRule.swift
//
//
//  Created by Coralogix DEV TEAM on 05/02/2026.
//

import Foundation

/// A per-URL rule that controls which headers and payloads the SDK captures for matching network requests.
///
/// Mirrors the browser SDK's `NetworkExtraConfig` interface:
/// ```
/// { url: string | RegExp; reqHeaders?: string[]; resHeaders?: string[]; collectReqPayload?: boolean; collectResPayload?: boolean; }
/// ```
///
/// **URL matching** (pick one initialiser):
/// - Plain string → substring match against the full absolute URL (case-insensitive), same as browser `url.includes(configUrl)`.
/// - `NSRegularExpression` → regex match against the full absolute URL string.
///
/// **Header capture** is allowlist-only: only names listed in `reqHeaders`/`resHeaders` are forwarded.
///
/// **Payload capture** is disabled by default and must be explicitly opted-in per rule.
public struct NetworkCaptureRule {

    // MARK: - URL matcher (internal — use matches(_:) from outside the module)

    /// Substring used for case-insensitive substring URL matching (empty when `urlPattern` is set).
    let url: String

    /// Regex applied against the full absolute URL string (nil when `url` is used).
    /// `urlPattern` takes precedence over `url` in `matches(_:)`.
    let urlPattern: NSRegularExpression?

    // MARK: - Capture settings

    /// Allowlisted request header names to capture. `nil` means "capture none".
    public let reqHeaders: [String]?

    /// Allowlisted response header names to capture. `nil` means "capture none".
    public let resHeaders: [String]?

    /// When `true`, the request body is captured and forwarded to Coralogix.
    public let collectReqPayload: Bool

    /// When `true`, the response body is captured and forwarded to Coralogix.
    public let collectResPayload: Bool

    // MARK: - Initialisers

    /// Creates a rule that matches requests whose absolute URL **contains** `url` (case-insensitive).
    /// - Precondition: `url` must not be empty. Use the `urlPattern` initialiser for wildcard/regex matching.
    public init(url: String,
                reqHeaders: [String]? = nil,
                resHeaders: [String]? = nil,
                collectReqPayload: Bool = false,
                collectResPayload: Bool = false) {
        precondition(!url.isEmpty, "NetworkCaptureRule: url must not be empty — use the urlPattern initialiser for pattern matching")
        self.url = url
        self.urlPattern = nil
        self.reqHeaders = reqHeaders
        self.resHeaders = resHeaders
        self.collectReqPayload = collectReqPayload
        self.collectResPayload = collectResPayload
    }

    /// Creates a rule that matches requests whose absolute URL satisfies the given `urlPattern` regex.
    public init(urlPattern: NSRegularExpression,
                reqHeaders: [String]? = nil,
                resHeaders: [String]? = nil,
                collectReqPayload: Bool = false,
                collectResPayload: Bool = false) {
        self.url = ""
        self.urlPattern = urlPattern
        self.reqHeaders = reqHeaders
        self.resHeaders = resHeaders
        self.collectReqPayload = collectReqPayload
        self.collectResPayload = collectResPayload
    }

    // MARK: - Internal matching

    /// Returns `true` when this rule applies to the given request URL.
    func matches(_ requestURL: URL) -> Bool {
        let absoluteString = requestURL.absoluteString
        if let pattern = urlPattern {
            let range = NSRange(absoluteString.startIndex..., in: absoluteString)
            return pattern.firstMatch(in: absoluteString, range: range) != nil
        }
        return absoluteString.range(of: url, options: .caseInsensitive) != nil
    }
}
