//
//  NetworkCaptureRule.swift
//
//
//  Created by Coralogix DEV TEAM on 05/02/2026.
//

import Foundation
import CoralogixInternal

/// A per-URL rule that controls which headers and payloads the SDK captures for matching network requests.
///
/// Mirrors the browser SDK's `NetworkExtraConfig` interface:
/// ```
/// { url: string | RegExp; reqHeaders?: string[]; resHeaders?: string[]; collectReqPayload?: boolean; collectResPayload?: boolean; }
/// ```
///
/// **URL matching** (pick one initialiser):
/// - Plain string → **case-insensitive substring** search against the absolute URL, same as
///   `url.includes(configUrl)` in the browser SDK.
/// - `NSRegularExpression` → **partial** (`firstMatch`) match against the absolute URL string.
///   Case sensitivity is controlled by the regex options you supply (default: case-sensitive).
///   Use `(?i)` in your pattern or pass `.caseInsensitive` when constructing the expression
///   if you want case-insensitive matching.
///
/// **Header capture** is allowlist-only: only names listed in `reqHeaders`/`resHeaders` are forwarded.
///
/// **Payload capture** is disabled by default and must be explicitly opted-in per rule.
public struct NetworkCaptureRule {

    // MARK: - Private URL matcher

    private enum Matcher {
        /// Case-insensitive substring search, mirroring `url.includes(configUrl)` in the browser SDK.
        case substring(String)
        /// Partial regex match (`firstMatch`) against the absolute URL string.
        /// Case sensitivity is determined by the `NSRegularExpression` options (default: case-sensitive).
        case regex(NSRegularExpression)
    }

    private let matcher: Matcher

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
    ///
    /// - Parameter url: A non-empty substring to search for. If an empty string is supplied the
    ///   rule is stored but will never match any request (safe no-op). Use the `urlPattern`
    ///   initialiser for wildcard/regex matching.
    public init(url: String,
                reqHeaders: [String]? = nil,
                resHeaders: [String]? = nil,
                collectReqPayload: Bool = false,
                collectResPayload: Bool = false) {
        if url.isEmpty {
            Log.w("NetworkCaptureRule created with an empty url — the rule will never match any request.")
        }
        self.matcher = .substring(url)
        self.reqHeaders = reqHeaders
        self.resHeaders = resHeaders
        self.collectReqPayload = collectReqPayload
        self.collectResPayload = collectResPayload
    }

    /// Creates a rule that matches requests whose absolute URL satisfies the given `urlPattern` regex.
    ///
    /// Matching uses `firstMatch` (partial/substring semantics). To anchor to the full URL, include
    /// `^` and `$` in your pattern. The regex is case-sensitive by default; pass `.caseInsensitive`
    /// in the `NSRegularExpression` options or use the `(?i)` flag in the pattern for case-insensitive
    /// matching.
    public init(urlPattern: NSRegularExpression,
                reqHeaders: [String]? = nil,
                resHeaders: [String]? = nil,
                collectReqPayload: Bool = false,
                collectResPayload: Bool = false) {
        self.matcher = .regex(urlPattern)
        self.reqHeaders = reqHeaders
        self.resHeaders = resHeaders
        self.collectReqPayload = collectReqPayload
        self.collectResPayload = collectResPayload
    }

    // MARK: - Internal matching

    /// Returns `true` when this rule applies to the given request URL.
    func matches(_ requestURL: URL) -> Bool {
        let absoluteString = requestURL.absoluteString
        switch matcher {
        case .substring(let substring):
            guard !substring.isEmpty else { return false }
            return absoluteString.range(of: substring, options: .caseInsensitive) != nil
        case .regex(let pattern):
            let range = NSRange(absoluteString.startIndex..., in: absoluteString)
            return pattern.firstMatch(in: absoluteString, range: range) != nil
        }
    }
}
