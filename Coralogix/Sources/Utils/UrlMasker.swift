//
//  UrlMasker.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

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
    /// The same, percent-encoded one level down: `?next=%2Freset%3Ftoken%3Dabc`. The name may itself
    /// hold percent-escapes (`%74oken`), other than the four delimiters, and is decoded before the check.
    private static let encodedParamPattern = regex("(%3F|%26|%23)((?:[A-Za-z0-9_.-]|%(?!3D|3F|26|23)[0-9A-F]{2})+)%3D((?:(?!%26|%23)[^&#])*)", .caseInsensitive)
    /// A JWT anywhere in the URL, the path included. The payload can be as short as `e30` (`{}`).
    /// A match starts only where a token run starts (or right after a `%XX` escape, as in
    /// `%3DeyJ…`), and the header is matched possessively: otherwise each `eyJ` inside a long run
    /// with no `.` starts its own scan to the end of the run, which is quadratic.
    private static let jwtPattern = regex("(?:(?<![A-Za-z0-9_-])|(?<=%[0-9A-Fa-f]{2}))eyJ[A-Za-z0-9_-]{8,}+\\.[A-Za-z0-9_-]{2,}(?:\\.[A-Za-z0-9_-]*){0,3}")
    /// Credentials written into the URL: `https://user:password@host`.
    /// Runs to the last `@` before the path, so a password holding an unencoded `@` is masked whole.
    private static let userInfoPattern = regex("^([a-z][a-z0-9+.-]*://)[^/?#]*@", .caseInsensitive)
    /// Session ids rewritten into the path: `/cart;jsessionid=…`.
    private static let pathSessionIdPattern = regex(";(jsessionid|phpsessid|sessionid|sid)=[^;/?#]*", .caseInsensitive)
    /// A URL with none of these cannot hold anything we mask.
    private static let maybeSensitivePattern = regex("[?#;@]|eyJ")
    private static let inlineDataPattern = regex("^(data|blob):", .caseInsensitive)

    /// How many redirect URLs nested inside one another are unwrapped; deeper values are redacted whole.
    private static let maxNestingDepth = 4
    /// A `fileName` value inside a stack-trace JSON array, as a raw JSON string literal.
    private static let fileNameValuePattern = regex("(\"\(Keys.fileName.rawValue)\"\\s*:\\s*)(\"(?:[^\"\\\\]|\\\\.)*\")")

    /// The customer's options with the parameter-name predicate built once, for masking many values.
    struct Masker {
        let options: UrlMaskingOptions
        private let shouldMask: (String) -> Bool

        init(_ options: UrlMaskingOptions = UrlMaskingOptions()) {
            self.options = options
            self.shouldMask = UrlMasker.paramPredicate(options)
        }

        func mask(_ url: String) -> String {
            UrlMasker.mask(url, shouldMask: shouldMask, dropQuery: options.mode == .dropQuery, depth: 0)
        }

        /// For a value that may be a URL or plain text: a view name (a route only in hybrid apps) or a
        /// userInfo string. A value with no whitespace is masked whole, and `.dropQuery` cuts it only
        /// when it is a URL or route, so a native name like `Step#2` keeps its `#`. Text with
        /// whitespace has only the URLs inside it masked, each on its own span, `.dropQuery`
        /// included: the words around them stay as they are, and a masked value cannot swallow the
        /// rest of the sentence.
        func maskUrlOrText(_ value: String) -> String {
            guard value.unicodeScalars.contains(where: { $0.properties.isWhitespace }) else {
                return UrlMasker.mask(value, shouldMask: shouldMask,
                                      dropQuery: UrlMasker.isUrlOrRoute(value) && options.mode == .dropQuery, depth: 0)
            }
            return UrlMasker.replacingUrlSpans(in: value) { mask($0) }
        }

        /// Masks only the `fileName` of each frame, the field that holds a script URL. Other frame
        /// text (`closure #1 in … == …`) looks like parameters and must be left alone, and the rest of
        /// the JSON is not re-serialized, so untouched values keep their exact bytes.
        func maskStackTrace(_ json: String) -> String {
            guard let pattern = UrlMasker.fileNameValuePattern else { return json }
            return UrlMasker.replace(pattern, in: json) { groups in
                // Fail closed: a file name we cannot read or write back is reported redacted.
                let redactedLiteral = "\(groups[1])\"\(UrlMasker.redacted)\""
                guard let data = groups[2].data(using: .utf8),
                      let fileName = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
                    return redactedLiteral
                }
                let masked = mask(fileName)
                guard masked != fileName else { return groups[0] }
                guard let out = try? JSONSerialization.data(withJSONObject: masked, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
                      let literal = String(data: out, encoding: .utf8) else {
                    return redactedLiteral
                }
                return groups[1] + literal
            }
        }

        /// Masks every string value inside a JSON document. Returns the input unchanged when nothing
        /// needed masking, and `nil` (drop the field) when it cannot be re-encoded: fail closed.
        func maskStrings(inJson json: String) -> String? {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return maskUrlOrText(json)
            }
            var changed = false
            func walk(_ value: Any) -> Any {
                switch value {
                case let string as String:
                    let masked = maskUrlOrText(string)
                    if masked != string { changed = true }
                    return masked
                case let array as [Any]:
                    return array.map(walk)
                case let dict as [String: Any]:
                    var out: [String: Any] = [:]
                    for (key, value) in dict {
                        let maskedKey = maskUrlOrText(key)
                        if maskedKey != key { changed = true }
                        // Two keys can mask to the same string; keep both instead of dropping one.
                        var uniqueKey = maskedKey
                        var suffix = 2
                        while out[uniqueKey] != nil {
                            uniqueKey = "\(maskedKey) (\(suffix))"
                            suffix += 1
                        }
                        out[uniqueKey] = walk(value)
                    }
                    return out
                default:
                    return value
                }
            }
            let masked = walk(object)
            guard changed else { return json }
            guard let out = try? JSONSerialization.data(withJSONObject: masked, options: [.fragmentsAllowed, .withoutEscapingSlashes]) else { return nil }
            return String(data: out, encoding: .utf8)
        }
    }

    static func mask(_ url: String, options: UrlMaskingOptions = UrlMaskingOptions()) -> String {
        Masker(options).mask(url)
    }

    static func maskStrings(inJson json: String, options: UrlMaskingOptions = UrlMaskingOptions()) -> String? {
        Masker(options).maskStrings(inJson: json)
    }

    private static func mask(_ url: String, shouldMask: (String) -> Bool, dropQuery: Bool, depth: Int) -> String {
        guard let maybeSensitivePattern, let inlineDataPattern, let userInfoPattern, let pathSessionIdPattern,
              let paramPattern, let encodedParamPattern, let jwtPattern else {
            // Fail closed: a URL we cannot mask is reported without the parts that hold secrets.
            return dropQueryAndFragment(url)
        }
        guard matches(maybeSensitivePattern, url), !matches(inlineDataPattern, url) else { return url }

        var result = dropQuery ? dropQueryAndFragment(url) : url
        result = replace(userInfoPattern, in: result) { "\($0[1])\(redacted)@" }
        result = replace(pathSessionIdPattern, in: result) { ";\($0[1])=\(redacted)" }
        result = replace(paramPattern, in: result) { groups in
            guard !groups[3].isEmpty else { return groups[0] }
            if shouldMask(groups[2]) { return "\(groups[1])\(groups[2])=\(redacted)" }
            // `?redirect=https://b.com/cb?token=abc`: the inner `?token=` is part of this match, so
            // matches never reach it on their own. Masking the value catches it.
            // Deliberately stricter than the browser SDK, which leaves the inner param as is.
            guard groups[3].contains("?") || groups[3].contains("#") else { return groups[0] }
            // Bounded so a crafted URL cannot recurse deep enough to exhaust the stack: fail closed.
            guard depth < maxNestingDepth else { return "\(groups[1])\(groups[2])=\(redacted)" }
            return "\(groups[1])\(groups[2])=\(mask(groups[3], shouldMask: shouldMask, dropQuery: dropQuery, depth: depth + 1))"
        }
        result = replace(encodedParamPattern, in: result) { groups in
            !groups[3].isEmpty && shouldMask(groups[2]) ? "\(groups[1])\(groups[2])%3D\(redacted)" : groups[0]
        }
        return replace(jwtPattern, in: result) { _ in redacted }
    }

    /// The whole value is one URL or route: no whitespace, and it starts with `/`, or with a scheme
    /// (a letter, then letters, digits, `+`, `.` or `-`) and `://`.
    static func isUrlOrRoute(_ value: String) -> Bool {
        guard !value.unicodeScalars.contains(where: { $0.properties.isWhitespace }) else { return false }
        if value.hasPrefix("/") { return true }
        guard let separator = value.range(of: "://") else { return false }
        let scheme = value[..<separator.lowerBound].unicodeScalars
        guard let first = scheme.first, first.isASCII, first.properties.isAlphabetic else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || "+.-".unicodeScalars.contains($0)) }
    }

    private static func isSchemeScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || "+.-".unicodeScalars.contains(scalar))
    }

    private static func endsUrl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || "\"'<>".unicodeScalars.contains(scalar)
    }

    /// Replaces each URL inside free text with `transform(url)`. A URL runs from its scheme to the
    /// next whitespace, `"`, `'`, `<` or `>`. A linear scan rather than a regex such as
    /// `scheme://\S+`, which is quadratic on long runs of letters: from each `://` it walks back
    /// over scheme characters, never past text already copied, then forward to the URL's end.
    static func replacingUrlSpans(in text: String, transform: (String) -> String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var copied = 0
        var index = 0
        while index + 2 < scalars.count {
            guard scalars[index] == ":", scalars[index + 1] == "/", scalars[index + 2] == "/" else {
                index += 1
                continue
            }
            var start = index
            while start > copied, isSchemeScalar(scalars[start - 1]) { start -= 1 }
            // The scheme must start with a letter: `1http://` begins at the `h`.
            while start < index, !(scalars[start].isASCII && scalars[start].properties.isAlphabetic) { start += 1 }
            guard start < index else {
                index += 3
                continue
            }
            var end = index + 3
            while end < scalars.count, !endsUrl(scalars[end]) { end += 1 }
            out.append(contentsOf: scalars[copied..<start])
            out.append(contentsOf: transform(String(String.UnicodeScalarView(scalars[start..<end]))).unicodeScalars)
            copied = end
            index = end
        }
        out.append(contentsOf: scalars[copied...])
        return String(out)
    }

    static func dropQueryAndFragment(_ url: String) -> String {
        guard let range = url.firstIndex(where: { $0 == "?" || $0 == "#" }) else { return url }
        return String(url[..<range])
    }

    fileprivate static func paramPredicate(_ options: UrlMaskingOptions) -> (String) -> Bool {
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
    fileprivate static func replace(_ regex: NSRegularExpression, in string: String,
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
