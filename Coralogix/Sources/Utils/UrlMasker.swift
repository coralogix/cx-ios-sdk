//
//  UrlMasker.swift
//  Coralogix
//

import Foundation

/// How the SDK masks secrets in the URLs it reports. Masking is always on: these options can only
/// add to the built-in rules, never remove one.
public struct UrlMaskingOptions {
    public enum Mode {
        /// Masks the values of sensitive parameters only. The default.
        case mask
        /// Masks the value of every query and fragment parameter, keeping the names.
        case maskAll
        /// Removes the query and the fragment.
        case dropQuery
    }

    /// A parameter name to mask on top of the built-in list.
    public enum Param: ExpressibleByStringLiteral {
        /// Matches the whole name, ignoring case and any non-alphanumeric character,
        /// so `"tenant_id"` also matches `TenantId` and `tenant-id`.
        case name(String)
        /// Tested against the percent-decoded name.
        case regex(NSRegularExpression)

        public init(stringLiteral value: String) {
            self = .name(value)
        }
    }

    public var additionalParams: [Param]
    public var mode: Mode

    public init(additionalParams: [Param] = [], mode: Mode = .mask) {
        self.additionalParams = additionalParams
        self.mode = mode
    }
}

/// Masks secrets in a URL before it is reported, keeping everything else byte-for-byte: the URL is
/// edited as a string and never re-serialized through `URL`, which would re-encode it.
/// The rules and patterns mirror the browser SDK so every RUM SDK reports a given URL the same way.
enum UrlMasker {
    static let redacted = "[REDACTED]"

    /// A parameter is sensitive when its normalized name contains one of these.
    private static let sensitiveNameFragments = [
        "token", "secret", "password", "passwd", "passphrase", "apikey", "signature", "credential",
        "jwt", "session", "sessid", "oauth", "saml", "privatekey", "accesskey", "nonce"
    ]

    /// Sensitive only as the whole normalized name: too short or common to match inside longer
    /// names (`code` must not catch `zipcode`, `auth` must not catch `author`).
    private static let sensitiveNames: Set<String> = [
        "code", "state", "codeverifier", "assertion", "clientassertion", "devicecode", "usercode",
        "bearer", "auth", "authorization", "authcode", "authkey", "sig", "hmac", "key",
        "pass", "pwd", "otp", "oobcode", "sid", "ticket"
    ]

    private static let maxParamNameLength = 64

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// Query and fragment parameters, including the query of a hash route (`#/reset?token=…`).
    /// The value runs to the next `&` or `#`, so a sensitive param holding an unencoded redirect URL
    /// is masked whole; a non-sensitive one holding such a URL has that URL masked in turn.
    private static let paramPattern = regex("([?&#])([^=&#?]+)=([^&#]*)")
    /// The same, percent-encoded one level down: `?next=%2Freset%3Ftoken%3Dabc`.
    private static let encodedParamPattern = regex("(%3F|%26|%23)([A-Za-z0-9_.-]+)%3D((?:(?!%26|%23)[^&#])*)", .caseInsensitive)
    /// A JWT anywhere in the URL, the path included.
    private static let jwtPattern = regex("eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}(?:\\.[A-Za-z0-9_-]*){0,3}")
    /// Credentials written into the URL: `https://user:password@host`.
    private static let userInfoPattern = regex("^([a-z][a-z0-9+.-]*://)[^/?#@]*@", .caseInsensitive)
    /// Session ids rewritten into the path: `/cart;jsessionid=…`.
    private static let pathSessionIdPattern = regex(";(jsessionid|phpsessid|sessionid|sid)=[^;/?#]*", .caseInsensitive)
    /// A URL with none of these cannot hold anything we mask.
    private static let maybeSensitivePattern = regex("[?#;@]|eyJ")
    private static let inlineDataPattern = regex("^(data|blob):", .caseInsensitive)

    static func mask(_ url: String, options: UrlMaskingOptions = UrlMaskingOptions()) -> String {
        guard let maybeSensitivePattern, let inlineDataPattern, let userInfoPattern, let pathSessionIdPattern,
              let paramPattern, let encodedParamPattern, let jwtPattern else {
            // Fail closed: a URL we cannot mask is reported without the parts that hold secrets.
            return dropQueryAndFragment(url)
        }
        guard matches(maybeSensitivePattern, url), !matches(inlineDataPattern, url) else { return url }
        let shouldMask = paramPredicate(options)

        var result = options.mode == .dropQuery ? dropQueryAndFragment(url) : url
        result = replace(userInfoPattern, in: result) { "\($0[1])\(redacted)@" }
        result = replace(pathSessionIdPattern, in: result) { ";\($0[1])=\(redacted)" }
        result = replace(paramPattern, in: result) { groups in
            guard !groups[3].isEmpty else { return groups[0] }
            if shouldMask(groups[2]) { return "\(groups[1])\(groups[2])=\(redacted)" }
            // `?redirect=https://b.com/cb?token=abc`: the inner `?token=` is part of this match, so
            // matches never reach it on their own. Masking the value catches it; the value is
            // strictly shorter than the URL, so this terminates.
            // Deliberately stricter than the browser SDK, which leaves the inner param as is.
            guard groups[3].contains("?") || groups[3].contains("#") else { return groups[0] }
            return "\(groups[1])\(groups[2])=\(mask(groups[3], options: options))"
        }
        result = replace(encodedParamPattern, in: result) { groups in
            !groups[3].isEmpty && shouldMask(groups[2]) ? "\(groups[1])\(groups[2])%3D\(redacted)" : groups[0]
        }
        return replace(jwtPattern, in: result) { _ in redacted }
    }

    /// Masks every string value inside a JSON document. Returns the input unchanged when nothing
    /// needed masking, and `nil` (drop the field) when it cannot be re-encoded: fail closed.
    static func maskStrings(inJson json: String, options: UrlMaskingOptions = UrlMaskingOptions()) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return mask(json, options: options)
        }
        var changed = false
        func walk(_ value: Any) -> Any {
            switch value {
            case let string as String:
                let masked = mask(string, options: options)
                if masked != string { changed = true }
                return masked
            case let array as [Any]:
                return array.map(walk)
            case let dict as [String: Any]:
                return dict.mapValues(walk)
            default:
                return value
            }
        }
        let masked = walk(object)
        guard changed else { return json }
        guard let out = try? JSONSerialization.data(withJSONObject: masked, options: [.fragmentsAllowed, .withoutEscapingSlashes]) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    static func dropQueryAndFragment(_ url: String) -> String {
        guard let range = url.firstIndex(where: { $0 == "?" || $0 == "#" }) else { return url }
        return String(url[..<range])
    }

    private static func paramPredicate(_ options: UrlMaskingOptions) -> (String) -> Bool {
        if options.mode == .maskAll { return { _ in true } }
        var extraNames = Set<String>()
        var extraRegexes: [NSRegularExpression] = []
        for param in options.additionalParams {
            switch param {
            case .name(let extra): extraNames.insert(normalize(extra))
            case .regex(let regex): extraRegexes.append(regex)
            }
        }
        return { rawName in
            guard rawName.count <= maxParamNameLength else { return false }
            let decoded = rawName.removingPercentEncoding ?? rawName
            let name = normalize(decoded)
            if sensitiveNames.contains(name) || extraNames.contains(name)
                || sensitiveNameFragments.contains(where: name.contains) {
                return true
            }
            return extraRegexes.contains { matches($0, decoded) }
        }
    }

    /// Lowercased without separators, so `api_key`, `API-Key` and `apiKey` compare equal.
    private static func normalize(_ name: String) -> String {
        // By scalar, not Character: a combining mark or ZWJ would otherwise hide a letter inside a grapheme.
        String(String.UnicodeScalarView(name.lowercased().unicodeScalars.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0)
        }))
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }

    /// Replaces every match with `transform(groups)`, where `groups[0]` is the whole match and a
    /// group that did not participate is "".
    private static func replace(_ regex: NSRegularExpression, in string: String,
                                transform: ([String]) -> String) -> String {
        let ns = string as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            result += transform(groups)
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}
