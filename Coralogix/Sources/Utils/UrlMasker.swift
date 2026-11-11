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

/// Masks secrets in URLs before they are reported. A port of the Android SDK's `UrlMaskingUtils`,
/// so every RUM SDK reports a given URL the same way; the shared cases live in `UrlMaskerTests`.
/// A URL is edited as a string, never re-serialized: in the default mode only masked values change,
/// `.maskAll` masks every parameter value, and `.dropQuery`, or a failure to mask, removes the query
/// and the fragment. Every scan is linear: the regexes are possessive and their start positions
/// cannot overlap, and the rest (credentials, JWTs, URLs inside text) are manual scans.
enum UrlMasker {
    static let redacted = "[REDACTED]"

    /// Sensitive when the normalized name contains one of these.
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

    /// Measured on the decoded name, so percent-encoding a short name cannot push it past the limit.
    private static let maxParamNameLength = 64

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    // Every unbounded run below is an atomic group around a greedy loop, not a possessive
    // quantifier inside a capture group: ICU keeps one backtrack entry per character for the
    // latter, overflows past ~180k characters and then reports no match at all, which would let a
    // long URL through unmasked. `replace` also treats any such abort as a failure (fail closed).

    /// Query and fragment parameters, the query of a hash route included. An HTML-escaped `&amp;`
    /// separates them as `&` does. The value runs to the next `&`, `#` or `;`. A name may be empty,
    /// which only `.maskAll` masks.
    private static let urlParamPattern = regex("([?#]|&(?:amp;)?)((?>[^=&#?;]*))=((?>[^&#;]*))")
    /// Parameters after `;`, and matrix parameters in a path; the value also stops at `?` and `/`.
    private static let semicolonParamPattern = regex("(;)((?>[^=&#?;/]+))=((?>[^&#;?/]*))")
    /// One level down: `?next=%2Freset%3Ftoken%3Dabc`, or a value that is itself an encoded
    /// parameter, `?return_to=code%3Dabc`. A name is any run up to the encoded `=` that holds none
    /// of the separators, so no two starts read the same characters; it is decoded before the test.
    private static let encodedParamPattern = regex(
        "(%3F|%26amp%3B|%26|%23|%3B|=)((?=[^%&#=\\s]|%(?!3D|26|23|3F|3B)[0-9A-F]{2})(?>[^%&#=\\s]*)(?:%(?!3D|26|23|3F|3B)[0-9A-F]{2}(?>[^%&#=\\s]*))*)"
            + "%3D((?>[^&#%]*)(?:%(?!26|23|3B)(?>[^&#%]*))*)",
        .caseInsensitive)
    /// A JWT: `eyJ` plus one more part however short (`e30` is `{}`), each with optional `=` padding.
    /// Tried only at the starts `maskJwts` picks, never searched for.
    private static let jwtPattern = regex("eyJ[A-Za-z0-9_-]{8,}={0,2}\\.[A-Za-z0-9_-]{2,}={0,2}(?:\\.[A-Za-z0-9_-]*={0,2}){0,3}")
    /// Session ids rewritten into the path: `/cart;jsessionid=…`. The value stops at `&` too.
    private static let pathSessionIdPattern = regex(";(jsessionid|phpsessid|sessionid|sid)=[^;/?#&]*", .caseInsensitive)
    /// A URL with none of these cannot hold anything masked. Encoded separators count, as in a path
    /// `/go/%3Ftoken%3Dabc`. `data:` and `blob:` URLs are masked like any other.
    private static let maybeSensitivePattern = regex("[?#;@&]|eyJ|%3F|%26|%23|%3B", .caseInsensitive)
    /// A `%` that does not start an escape, kept as a literal so the rest of a name still decodes.
    private static let strayPercentPattern = regex("%(?![0-9A-Fa-f]{2})")
    /// A `fileName` value inside a stack-trace JSON array, as a raw JSON string literal.
    private static let fileNameValuePattern = regex("(\"\(Keys.fileName.rawValue)\"\\s*:\\s*)(\"(?>[^\"\\\\]*)(?:\\\\.(?>[^\"\\\\]*))*\")")
    /// Any JSON string literal, and the `:` after it when it is an object key.
    private static let jsonStringPattern = regex("(\"(?>[^\"\\\\]*)(?:\\\\.(?>[^\"\\\\]*))*\")(\\s*:)?")

    /// How many redirect URLs nested inside one another are unwrapped; deeper values are redacted whole.
    private static let maxNestingDepth = 4

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

        /// A view name is a route only in hybrid apps, and is then masked as a URL. Otherwise each
        /// URL inside it is masked (`.dropQuery` included), then sensitive parameters in the rest,
        /// without dropping anything: a native name such as `Step #2` keeps its `#`.
        func maskViewName(_ name: String) -> String {
            if UrlMasker.isUrlOrRoute(name) { return mask(name) }
            return UrlMasker.mask(maskText(name), shouldMask: shouldMask, dropQuery: false, depth: 0)
        }

        /// Masks each URL inside free text, such as an error message; the words around them are
        /// kept, and text that is not a URL is never masked. A value that is wholly a root-relative
        /// route (`/reset?token=…`), which the URL scan cannot find, is masked as one: stricter than
        /// the Android SDK. Scheme and `//` URLs stay with the scan, which leaves unmatched closing
        /// brackets outside them.
        func maskText(_ text: String) -> String {
            if text.hasPrefix("/"), !text.hasPrefix("//"), UrlMasker.isUrlOrRoute(text) { return mask(text) }
            return UrlMasker.maskUrlsInText(text) { mask($0) }
        }

        /// Masks only the `fileName` of each frame, the field that holds a script URL. Other frame
        /// text (`closure #1 in … == …`) looks like parameters and must be left alone.
        /// `nil` when the JSON could not be scanned: the caller drops the field (fail closed).
        func maskStackTrace(_ json: String) -> String? {
            guard let pattern = UrlMasker.fileNameValuePattern else { return nil }
            return UrlMasker.replace(pattern, in: json) { groups in
                guard let literal = UrlMasker.maskingJsonLiteral(groups[2], with: mask) else { return groups[0] }
                return groups[1] + literal
            }
        }

        /// Masks the URLs inside every string of a userInfo JSON document, keys included, editing
        /// each changed string literal in place so the rest keeps its exact bytes.
        /// `nil` when the JSON could not be scanned: the caller drops the field (fail closed).
        func maskUserInfo(_ json: String) -> String? {
            guard let pattern = UrlMasker.jsonStringPattern else { return nil }
            var keyOwners: [String: String] = [:]
            return UrlMasker.replace(pattern, in: json) { groups in
                let literal = groups[1]
                guard let masked = UrlMasker.maskingJsonLiteral(literal, with: maskText) else { return groups[0] }
                let isKey = !groups[2].isEmpty
                guard isKey else { return masked }
                // Two keys can mask to the same string; number the later ones so no member is lost
                // when the JSON is parsed.
                var key = masked
                var suffix = 2
                while let owner = keyOwners[key], owner != literal {
                    key = String(masked.dropLast()) + " (\(suffix))\""
                    suffix += 1
                }
                keyOwners[key] = literal
                return key + groups[2]
            }
        }
    }

    static func mask(_ url: String, options: UrlMaskingOptions = UrlMaskingOptions()) -> String {
        Masker(options).mask(url)
    }

    static func maskUrlsInText(_ text: String, options: UrlMaskingOptions = UrlMaskingOptions()) -> String {
        Masker(options).maskText(text)
    }

    /// `nil` when the literal is unchanged. A literal that cannot be read or written back is
    /// reported redacted: fail closed.
    private static func maskingJsonLiteral(_ literal: String, with transform: (String) -> String) -> String? {
        let redactedLiteral = "\"\(redacted)\""
        guard let data = literal.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
            return redactedLiteral
        }
        let masked = transform(value)
        guard masked != value else { return nil }
        guard let out = try? JSONSerialization.data(withJSONObject: masked, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let encoded = String(data: out, encoding: .utf8) else {
            return redactedLiteral
        }
        return encoded
    }

    private static func mask(_ url: String, shouldMask: (String) -> Bool, dropQuery: Bool, depth: Int) -> String {
        guard let maybeSensitivePattern, matches(maybeSensitivePattern, url) else { return url }
        guard let urlParamPattern, let semicolonParamPattern, let encodedParamPattern, jwtPattern != nil else {
            return failClosed(url)
        }
        // A JWT in the path or a `user:password@` survives a dropped query, so the rest still runs.
        let base = maskOutsideParams(dropQuery ? dropQueryAndFragment(url) : url)
        guard let params = replace(urlParamPattern, in: base, transform: { groups in
            guard !groups[3].isEmpty else { return groups[0] }
            if shouldMask(groups[2]) { return "\(groups[1])\(groups[2])=\(redacted)" }
            // `?redirect=https://b.com/cb?token=abc`: the inner `?token=` is part of this match, so
            // matches never reach it on their own. Masking the value catches it. Stricter than the
            // browser and Android SDKs, which leave the inner parameter as is.
            guard groups[3].contains("?") else { return groups[0] }
            // Bounded so a crafted URL cannot recurse deep enough to exhaust the stack: fail closed.
            guard depth < maxNestingDepth else { return "\(groups[1])\(groups[2])=\(redacted)" }
            return "\(groups[1])\(groups[2])=\(mask(groups[3], shouldMask: shouldMask, dropQuery: false, depth: depth + 1))"
        }),
              let semicolonParams = replace(semicolonParamPattern, in: params, transform: { groups in
            !groups[3].isEmpty && shouldMask(groups[2]) ? "\(groups[1])\(groups[2])=\(redacted)" : groups[0]
        }),
              let encodedParams = replace(encodedParamPattern, in: semicolonParams, transform: { groups in
            !groups[3].isEmpty && shouldMask(groups[2]) ? "\(groups[1])\(groups[2])%3D\(redacted)" : groups[0]
        }) else {
            return failClosed(url)
        }
        return maskJwts(encodedParams)
    }

    /// When masking cannot run to completion: drop the query, the fragment and anything after an
    /// encoded separator (a path such as `/go/%3Ftoken%3D…` carries its query encoded), then still
    /// mask credentials, path session ids and JWTs in what remains.
    private static func failClosed(_ url: String) -> String {
        var kept = dropQueryAndFragment(url)
        if let cut = ["%3F", "%23", "%26", "%3B"].compactMap({ kept.range(of: $0, options: .caseInsensitive)?.lowerBound }).min() {
            kept = String(kept[..<cut])
        }
        return maskJwts(maskOutsideParams(kept))
    }

    /// Credentials and path session ids: the parts of a URL that are not parameters.
    private static func maskOutsideParams(_ url: String) -> String {
        let withoutCredentials = maskCredentials(url)
        guard let pathSessionIdPattern,
              let masked = replace(pathSessionIdPattern, in: withoutCredentials, transform: { ";\($0[1])=\(redacted)" }) else {
            return dropQueryAndFragment(withoutCredentials)
        }
        return masked
    }

    // MARK: - Manual scans, on UTF-16 code units like the regexes

    private static func units(_ string: String) -> [UInt16] { Array(string.utf16) }

    private static func string(_ units: ArraySlice<UInt16>) -> String {
        String(decoding: units, as: UTF16.self)
    }

    private static let slash = UInt16(UInt8(ascii: "/"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let colon = UInt16(UInt8(ascii: ":"))
    private static let at = UInt16(UInt8(ascii: "@"))
    private static let question = UInt16(UInt8(ascii: "?"))
    private static let hash = UInt16(UInt8(ascii: "#"))
    private static let doubleQuote = UInt16(UInt8(ascii: "\""))
    private static let apostrophe = UInt16(UInt8(ascii: "'"))
    private static let lessThan = UInt16(UInt8(ascii: "<"))
    private static let greaterThan = UInt16(UInt8(ascii: ">"))

    private static func isAsciiLetter(_ unit: UInt16) -> Bool {
        (65...90).contains(unit) || (97...122).contains(unit)
    }

    private static func isSchemeUnit(_ unit: UInt16) -> Bool {
        isAsciiLetter(unit) || (48...57).contains(unit) || unit == 43 || unit == 46 || unit == 45
    }

    private static func isBase64UrlUnit(_ unit: UInt16) -> Bool {
        isAsciiLetter(unit) || (48...57).contains(unit) || unit == 95 || unit == 45
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        Unicode.Scalar(unit)?.properties.isWhitespace ?? false
    }

    private static func isLetterOrDigit(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
            return true
        default:
            return false
        }
    }

    private static func slashRunEnd(_ text: [UInt16], from: Int) -> Int {
        var end = from
        while end < text.count, text[end] == slash || text[end] == backslash { end += 1 }
        return end
    }

    /// Credentials, masked up to the last `@` of the authority as URL parsers read it, so an
    /// unencoded `@` or `'` in the password is masked too. An authority starts after `scheme:` and
    /// two or more slashes (backslashes and JSON-escaped `\/\/` included) anywhere in the URL; after
    /// a leading `//`; or, at the start, right after a scheme with no slashes. It ends at the next
    /// `/`, `?`, `#` or whitespace. One pass: each authority read is skipped.
    private static func maskCredentials(_ url: String) -> String {
        guard url.contains("@") else { return url }
        let text = units(url)
        var result = ""
        var copied = 0
        var next = leadingAuthorityStart(text)
        var index = next ?? 0
        while index < text.count {
            let start = next ?? slashedAuthorityStart(text, at: index)
            next = nil
            guard let start else {
                index += 1
                continue
            }
            var end = start
            var lastAt = -1
            while end < text.count {
                let unit = text[end]
                if unit == slash || unit == question || unit == hash || isWhitespace(unit) { break }
                if unit == at { lastAt = end }
                end += 1
            }
            if lastAt >= 0 {
                result += string(text[copied..<start]) + redacted
                copied = lastAt
            }
            index = max(end, start + 1)
        }
        return result + string(text[copied...])
    }

    /// After a leading `//` (or `\/\/`), or after a scheme with no slashes, at the start.
    private static func leadingAuthorityStart(_ text: [UInt16]) -> Int? {
        var index = 0
        while index < text.count, isWhitespace(text[index]) { index += 1 }
        let slashes = slashRunEnd(text, from: index)
        if slashes - index >= 2 { return slashes }
        if index < text.count, isAsciiLetter(text[index]) {
            var schemeEnd = index
            while schemeEnd < text.count, isSchemeUnit(text[schemeEnd]) { schemeEnd += 1 }
            if schemeEnd < text.count, text[schemeEnd] == colon, slashRunEnd(text, from: schemeEnd + 1) == schemeEnd + 1 {
                return schemeEnd + 1
            }
        }
        return nil
    }

    /// After `:` and two or more slashes or backslashes, when `index` is that `:`.
    private static func slashedAuthorityStart(_ text: [UInt16], at index: Int) -> Int? {
        guard text[index] == colon else { return nil }
        let slashes = slashRunEnd(text, from: index + 1)
        return slashes - (index + 1) >= 2 ? slashes : nil
    }

    /// Replaces each JWT in one pass. A start that fails fails for every later `eyJ` in the same
    /// run of base64url characters, which reaches the same end, so the scan moves past the run.
    private static func maskJwts(_ url: String) -> String {
        guard url.contains("eyJ"), let jwtPattern else { return url }
        let text = units(url)
        let nsUrl = url as NSString
        var result = ""
        var copied = 0
        var start = indexOf(Array("eyJ".utf16), in: text, from: 0)
        while let found = start {
            let next: Int
            if let match = jwtPattern.firstMatch(in: url, options: [.anchored],
                                                 range: NSRange(location: found, length: nsUrl.length - found)) {
                result += string(text[copied..<found]) + redacted
                copied = match.range.location + match.range.length
                next = copied
            } else {
                var end = found + 3
                while end < text.count, isBase64UrlUnit(text[end]) { end += 1 }
                next = end
            }
            start = indexOf(Array("eyJ".utf16), in: text, from: next)
        }
        return result + string(text[copied...])
    }

    private static func indexOf(_ needle: [UInt16], in text: [UInt16], from: Int) -> Int? {
        guard !needle.isEmpty, from >= 0 else { return nil }
        var index = from
        while index + needle.count <= text.count {
            if text[index] == needle[0] {
                var offset = 1
                while offset < needle.count, text[index + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { return index }
            }
            index += 1
        }
        return nil
    }

    /// JSON escapes slashes, so a URL in a JSON error body reads `https:\/\/host\/…`.
    private static let escapedSlashes = Array("\\/\\/".utf16)
    private static let plainSlashes = Array("//".utf16)

    /// Masks each URL inside free text with `transform`; the words around them are kept. A URL runs
    /// from its scheme, or from the `//` of a protocol-relative URL that starts a word, to the next
    /// whitespace, `"`, `<`, `>` or escaped `\"`; an apostrophe ends it only when an apostrophe opened
    /// it, and a closing bracket the URL never opened is left out of it. Found by scanning from each
    /// `//` (or `\/\/`), each kind searched again only once the scan has passed the last one found.
    static func maskUrlsInText(_ value: String, transform: (String) -> String) -> String {
        let text = units(value)
        var plainAt = indexOf(plainSlashes, in: text, from: 0)
        var escapedAt = indexOf(escapedSlashes, in: text, from: 0)
        func nextSlashes(from: Int) -> Int? {
            if let p = plainAt, p < from { plainAt = indexOf(plainSlashes, in: text, from: from) }
            if let e = escapedAt, e < from { escapedAt = indexOf(escapedSlashes, in: text, from: from) }
            switch (plainAt, escapedAt) {
            case (nil, nil): return nil
            case (let p?, nil): return p
            case (nil, let e?): return e
            case (let p?, let e?): return min(p, e)
            }
        }
        guard var slashes = nextSlashes(from: 0) else { return value }
        var result = ""
        var copied = 0
        while true {
            let isEscaped = slashes + escapedSlashes.count <= text.count
                && Array(text[slashes..<(slashes + escapedSlashes.count)]) == escapedSlashes
            let afterSlashes = slashes + (isEscaped ? escapedSlashes.count : 2)
            var schemeStart: Int?
            if slashes > 0, text[slashes - 1] == colon {
                // scheme://…: back over the scheme, which starts with a letter.
                let schemeColon = slashes - 1
                var s = schemeColon
                while s > copied, isSchemeUnit(text[s - 1]) { s -= 1 }
                while s < schemeColon, !isAsciiLetter(text[s]) { s += 1 }
                if s < schemeColon { schemeStart = s }
            }
            // //host…, or what follows a `:` no scheme precedes: a URL when the `//` starts a word
            // and something other than a space or another slash follows, so `a // b` and
            // `path//to` stay prose.
            var start = schemeStart
            if start == nil {
                let startsWord = slashes == 0 || {
                    let before = text[slashes - 1]
                    return !isLetterOrDigit(before) && before != slash && before != backslash
                }()
                if startsWord, afterSlashes < text.count {
                    let after = text[afterSlashes]
                    if !isWhitespace(after), after != slash, after != backslash { start = slashes }
                }
            }
            guard let urlStart = start else {
                // Right after the rejected `//`, not past its word: a URL can still follow in it.
                guard let following = nextSlashes(from: slashes + 1) else { break }
                slashes = following
                continue
            }
            let quotedBySingle = urlStart > 0 && text[urlStart - 1] == apostrophe
            var end = afterSlashes
            while end < text.count, !endsUrl(text, at: end, quotedBySingle: quotedBySingle) { end += 1 }
            // A closing bracket the URL never opened is the text's; balanced ones (an IPv6 host's)
            // stay. Counted once, then kept as each closer is trimmed.
            var unmatched = [0, 0, 0]
            for i in urlStart..<end {
                switch text[i] {
                case 40: unmatched[0] -= 1
                case 41: unmatched[0] += 1
                case 91: unmatched[1] -= 1
                case 93: unmatched[1] += 1
                case 123: unmatched[2] -= 1
                case 125: unmatched[2] += 1
                default: break
                }
            }
            while end > afterSlashes {
                let kind: Int
                switch text[end - 1] {
                case 41: kind = 0
                case 93: kind = 1
                case 125: kind = 2
                default: kind = -1
                }
                guard kind >= 0, unmatched[kind] > 0 else { break }
                unmatched[kind] -= 1
                end -= 1
            }
            result += string(text[copied..<urlStart]) + transform(string(text[urlStart..<end]))
            copied = end
            guard let following = nextSlashes(from: end) else { break }
            slashes = following
        }
        return result + string(text[copied...])
    }

    /// Whitespace, `"`, `<`, `>` or the `\"` of an escaped quote; an apostrophe only when quoted with one.
    private static func endsUrl(_ text: [UInt16], at index: Int, quotedBySingle: Bool) -> Bool {
        let unit = text[index]
        return isWhitespace(unit) || unit == doubleQuote || (unit == apostrophe && quotedBySingle)
            || unit == lessThan || unit == greaterThan
            || (unit == backslash && index + 1 < text.count && text[index + 1] == doubleQuote)
    }

    /// The whole value is one URL or route: no whitespace, and it starts with `/`, or with a scheme
    /// (a letter, then letters, digits, `+`, `.` or `-`) and `://`.
    static func isUrlOrRoute(_ value: String) -> Bool {
        let text = units(value)
        guard !text.contains(where: isWhitespace) else { return false }
        if text.first == slash { return true }
        guard let first = text.first, isAsciiLetter(first) else { return false }
        var index = 0
        while index < text.count, isSchemeUnit(text[index]) { index += 1 }
        return index + 2 < text.count && text[index] == colon && text[index + 1] == slash && text[index + 2] == slash
    }

    /// Drops everything from the first `?` or `#`, line breaks included.
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
            let decoded = decode(rawName)
            guard decoded.utf16.count <= maxParamNameLength else { return false }
            let name = normalize(decoded)
            if sensitiveNames.contains(name) || extraNames.contains(name)
                || sensitiveNameFragments.contains(where: name.contains) {
                return true
            }
            return extraRegexes.contains { matches($0, decoded) }
        }
    }

    /// Lenient: a stray `%` is kept as a literal so the rest still decodes, and `+` stays `+`, as
    /// JavaScript's `decodeURIComponent` keeps it, so a pattern matches the same names in every SDK.
    private static func decode(_ name: String) -> String {
        guard let strayPercentPattern else { return name.removingPercentEncoding ?? name }
        guard let escaped = replace(strayPercentPattern, in: name, transform: { _ in "%25" }) else { return name }
        return escaped.removingPercentEncoding ?? name
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
    /// group that did not participate is "". `nil` when ICU stops early (it reports an internal
    /// error, such as its backtrack stack overflowing, rather than throwing), so the caller can
    /// fail closed instead of mistaking it for "nothing matched".
    fileprivate static func replace(_ regex: NSRegularExpression, in string: String,
                                    transform: ([String]) -> String) -> String? {
        let ns = string as NSString
        var result = ""
        var cursor = 0
        var failed = false
        regex.enumerateMatches(in: string, options: [.reportCompletion],
                               range: NSRange(location: 0, length: ns.length)) { match, flags, stop in
            if flags.contains(.internalError) {
                failed = true
                stop.pointee = true
                return
            }
            guard let match else { return }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            result += transform(groups)
            cursor = match.range.location + match.range.length
        }
        guard !failed else { return nil }
        result += ns.substring(from: cursor)
        return result
    }
}
