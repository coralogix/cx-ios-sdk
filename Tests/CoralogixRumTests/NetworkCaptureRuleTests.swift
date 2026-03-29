//
//  NetworkCaptureRuleTests.swift
//
//
//  Created by Coralogix DEV TEAM on 05/02/2026.
//

import XCTest
@testable import Coralogix

final class NetworkCaptureRuleTests: XCTestCase {

    // MARK: - matches(_:) — string init

    func testMatches_exactSubstring_returnsTrue() throws {
        let rule = NetworkCaptureRule(url: "api.example.com")
        let url = try XCTUnwrap(URL(string: "https://api.example.com/users"))
        XCTAssertTrue(rule.matches(url))
    }

    func testMatches_substring_caseInsensitive_returnsTrue() throws {
        let rule = NetworkCaptureRule(url: "API.EXAMPLE.COM")
        let url = try XCTUnwrap(URL(string: "https://api.example.com/users"))
        XCTAssertTrue(rule.matches(url))
    }

    func testMatches_noSubstringMatch_returnsFalse() throws {
        let rule = NetworkCaptureRule(url: "other.com")
        let url = try XCTUnwrap(URL(string: "https://api.example.com/users"))
        XCTAssertFalse(rule.matches(url))
    }

    func testMatches_substringInPath_returnsTrue() throws {
        // Substring matching covers the full absolute URL, not just the host.
        let rule = NetworkCaptureRule(url: "users")
        let url = try XCTUnwrap(URL(string: "https://api.example.com/users/42"))
        XCTAssertTrue(rule.matches(url))
    }

    func testMatches_substringInQuery_returnsTrue() throws {
        let rule = NetworkCaptureRule(url: "search")
        let url = try XCTUnwrap(URL(string: "https://api.example.com/endpoint?search=foo"))
        XCTAssertTrue(rule.matches(url))
    }

    // MARK: - matches(_:) — regex init

    func testMatches_regex_matchingPattern_returnsTrue() throws {
        let pattern = try NSRegularExpression(pattern: "api\\.example\\.com/users/\\d+")
        let rule = NetworkCaptureRule(urlPattern: pattern)
        let url = try XCTUnwrap(URL(string: "https://api.example.com/users/42"))
        XCTAssertTrue(rule.matches(url))
    }

    func testMatches_regex_nonMatchingPattern_returnsFalse() throws {
        let pattern = try NSRegularExpression(pattern: "api\\.example\\.com/orders/\\d+")
        let rule = NetworkCaptureRule(urlPattern: pattern)
        let url = try XCTUnwrap(URL(string: "https://api.example.com/users/42"))
        XCTAssertFalse(rule.matches(url))
    }

    // MARK: - Default values

    func testDefaults_stringInit_allCaptureDisabled() {
        let rule = NetworkCaptureRule(url: "example.com")
        XCTAssertNil(rule.reqHeaders)
        XCTAssertNil(rule.resHeaders)
        XCTAssertFalse(rule.collectReqPayload)
        XCTAssertFalse(rule.collectResPayload)
    }

    func testDefaults_regexInit_allCaptureDisabled() throws {
        let pattern = try NSRegularExpression(pattern: ".*")
        let rule = NetworkCaptureRule(urlPattern: pattern)
        XCTAssertNil(rule.reqHeaders)
        XCTAssertNil(rule.resHeaders)
        XCTAssertFalse(rule.collectReqPayload)
        XCTAssertFalse(rule.collectResPayload)
    }

    // MARK: - CoralogixExporterOptions wiring

    func testOptions_networkExtraConfig_defaultsToNil() {
        let options = makeOptions()
        XCTAssertNil(options.networkExtraConfig)
    }

    func testOptions_networkExtraConfig_storesRules() throws {
        let rule = NetworkCaptureRule(url: "api.example.com",
                                     reqHeaders: ["Authorization"],
                                     collectResPayload: true)
        var options = makeOptions()
        options.networkExtraConfig = [rule]
        XCTAssertEqual(options.networkExtraConfig?.count, 1)
        // Verify capture settings are preserved (public API).
        XCTAssertEqual(options.networkExtraConfig?.first?.reqHeaders, ["Authorization"])
        XCTAssertEqual(options.networkExtraConfig?.first?.collectResPayload, true)
        // Verify the stored rule matches behaviorally rather than inspecting internal state.
        let matchingURL = try XCTUnwrap(URL(string: "https://api.example.com/endpoint"))
        XCTAssertTrue(options.networkExtraConfig?.first?.matches(matchingURL) == true)
    }

    // MARK: - resolveConfigForUrl(_:configs:)

    func testResolveConfigForUrl_substringMatch_returnsMatchingRule() throws {
        let rule = NetworkCaptureRule(url: "api.example.com", collectReqPayload: true)
        let result = try XCTUnwrap(resolveConfigForUrl("https://api.example.com/users", configs: [rule]))
        XCTAssertTrue(result.collectReqPayload)
    }

    func testResolveConfigForUrl_regexMatch_returnsMatchingRule() throws {
        let pattern = try NSRegularExpression(pattern: "example\\.com/users/\\d+")
        let rule = NetworkCaptureRule(urlPattern: pattern, collectResPayload: true)
        let result = try XCTUnwrap(resolveConfigForUrl("https://api.example.com/users/42", configs: [rule]))
        XCTAssertTrue(result.collectResPayload)
    }

    func testResolveConfigForUrl_noMatch_returnsNil() {
        let rule = NetworkCaptureRule(url: "other.com")
        let result = resolveConfigForUrl("https://api.example.com/users", configs: [rule])
        XCTAssertNil(result)
    }

    func testResolveConfigForUrl_emptyConfigs_returnsNil() {
        let result = resolveConfigForUrl("https://api.example.com/users", configs: [])
        XCTAssertNil(result)
    }

    func testResolveConfigForUrl_invalidUrl_returnsNil() {
        let rule = NetworkCaptureRule(url: "example.com")
        // "not a url" cannot be parsed as URL — must return nil gracefully.
        let result = resolveConfigForUrl("not a url ://??", configs: [rule])
        XCTAssertNil(result)
    }

    func testResolveConfigForUrl_nonMatchingRuleBeforeMatchingRule_returnsMatchingRule() throws {
        let nonMatching = NetworkCaptureRule(url: "other.com")
        let matching    = NetworkCaptureRule(url: "example.com", collectReqPayload: true)
        let result = try XCTUnwrap(resolveConfigForUrl("https://api.example.com/users", configs: [nonMatching, matching]))
        XCTAssertTrue(result.collectReqPayload)
    }

    // MARK: - resolveConfigForUrl — merge semantics (multiple matching rules)

    func testResolveConfigForUrl_multipleMatchingRules_mergesReqHeaders() {
        let broadRule    = NetworkCaptureRule(url: "example.com",   reqHeaders: ["Content-Type", "Accept"])
        let specificRule = NetworkCaptureRule(url: "example.com/v2", reqHeaders: ["traceparent", "X-Custom"])
        let result = resolveConfigForUrl("https://api.example.com/v2/items", configs: [broadRule, specificRule])
        let merged = Set(result?.reqHeaders ?? [])
        XCTAssertEqual(merged, ["Content-Type", "Accept", "traceparent", "X-Custom"],
                       "reqHeaders from all matching rules must be unioned")
    }

    func testResolveConfigForUrl_multipleMatchingRules_mergesResHeaders() {
        let ruleA = NetworkCaptureRule(url: "example.com", resHeaders: ["Content-Type"])
        let ruleB = NetworkCaptureRule(url: "example.com", resHeaders: ["X-Request-Id"])
        let result = resolveConfigForUrl("https://api.example.com/data", configs: [ruleA, ruleB])
        let merged = Set(result?.resHeaders ?? [])
        XCTAssertEqual(merged, ["Content-Type", "X-Request-Id"])
    }

    func testResolveConfigForUrl_multipleMatchingRules_collectPayloadTrueIfAnyRuleEnablesIt() {
        let noPayload  = NetworkCaptureRule(url: "example.com",   collectResPayload: false)
        let hasPayload = NetworkCaptureRule(url: "example.com/v2", collectResPayload: true)
        let result = resolveConfigForUrl("https://api.example.com/v2/items", configs: [noPayload, hasPayload])
        XCTAssertTrue(result?.collectResPayload == true,
                      "collectResPayload must be true when any matching rule enables it")
    }

    func testResolveConfigForUrl_multipleMatchingRules_collectPayloadFalseWhenNoRuleEnablesIt() {
        let ruleA = NetworkCaptureRule(url: "example.com",   collectResPayload: false)
        let ruleB = NetworkCaptureRule(url: "example.com/v2", collectResPayload: false)
        let result = resolveConfigForUrl("https://api.example.com/v2/items", configs: [ruleA, ruleB])
        XCTAssertFalse(result?.collectResPayload == true)
    }

    func testResolveConfigForUrl_multipleMatchingRules_allNilReqHeaders_mergedIsNil() {
        let ruleA = NetworkCaptureRule(url: "example.com")   // reqHeaders: nil
        let ruleB = NetworkCaptureRule(url: "example.com/v2") // reqHeaders: nil
        let result = resolveConfigForUrl("https://api.example.com/v2/items", configs: [ruleA, ruleB])
        XCTAssertNil(result?.reqHeaders,
                     "Merged reqHeaders must be nil when all matching rules have nil reqHeaders")
    }

    /// Regression: broad rule (no traceparent) + specific rule (with traceparent) — merged allowlist must include traceparent.
    /// This is the RN hybrid scenario: Rule 1 matches the host broadly, Rule 5 matches the specific path and adds traceparent.
    func testResolveConfigForUrl_broadAndSpecificRule_traceparentIncludedInMergedAllowlist() {
        let broadRule    = NetworkCaptureRule(url: "jsonplaceholder.typicode.com",
                                             reqHeaders: ["content-type", "accept"],
                                             collectResPayload: true)
        let specificRule = NetworkCaptureRule(url: "jsonplaceholder.typicode.com/posts/1",
                                             reqHeaders: ["accept", "traceparent"],
                                             collectResPayload: false)
        let result = resolveConfigForUrl("https://jsonplaceholder.typicode.com/posts/1", configs: [broadRule, specificRule])
        let merged = Set(result?.reqHeaders ?? [])
        XCTAssertTrue(merged.contains("traceparent"),
                      "traceparent must appear in the merged allowlist even if only the specific rule lists it")
        XCTAssertTrue(result?.collectResPayload == true,
                      "collectResPayload must be true because the broad rule enables it")
    }

    func testResolveConfigForUrl_singleMatchingRule_returnedUnchanged() throws {
        let rule = NetworkCaptureRule(url: "example.com",
                                     reqHeaders: ["Authorization"],
                                     collectReqPayload: true)
        let result = try XCTUnwrap(resolveConfigForUrl("https://api.example.com/users", configs: [rule]))
        XCTAssertEqual(result.reqHeaders, ["Authorization"])
        XCTAssertTrue(result.collectReqPayload)
    }

    func testResolveConfigForUrl_captureSettingsPreserved() throws {
        let rule = NetworkCaptureRule(url: "example.com",
                                     reqHeaders: ["Authorization", "X-Custom"],
                                     resHeaders: ["Content-Type"],
                                     collectReqPayload: true,
                                     collectResPayload: false)
        let result = try XCTUnwrap(
            resolveConfigForUrl("https://api.example.com/endpoint", configs: [rule])
        )
        XCTAssertEqual(result.reqHeaders, ["Authorization", "X-Custom"])
        XCTAssertEqual(result.resHeaders, ["Content-Type"])
        XCTAssertTrue(result.collectReqPayload)
        XCTAssertFalse(result.collectResPayload)
    }

    func testResolveConfigForUrl_mixedRules_regexMatchesWhenSubstringDoesNot() throws {
        let substringRule = NetworkCaptureRule(url: "other.com")
        let regexPattern  = try NSRegularExpression(pattern: "example\\.com/v2")
        let regexRule     = NetworkCaptureRule(urlPattern: regexPattern, collectResPayload: true)

        let result = try XCTUnwrap(resolveConfigForUrl("https://api.example.com/v2/items",
                                                       configs: [substringRule, regexRule]))
        XCTAssertTrue(result.collectResPayload)
    }

    // MARK: - filterHeaders(_:allowlist:) (CX-33233)

    func testFilterHeaders_allowlistHit_includesHeaderWithConfigKeyCasing() {
        let headers = ["Content-Type": "application/json", "X-Other": "ignored"]
        let allowlist = ["Content-Type"]
        let result = NetworkCaptureRule.filterHeaders(headers, allowlist: allowlist)
        XCTAssertEqual(result, ["Content-Type": "application/json"],
                       "Output key must use allowlist (config) casing")
    }

    func testFilterHeaders_allowlistMiss_excludesHeader() {
        let headers = ["Authorization": "Bearer x", "X-Custom": "y"]
        let allowlist = ["Content-Type"]
        let result = NetworkCaptureRule.filterHeaders(headers, allowlist: allowlist)
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterHeaders_caseInsensitive_matchAndPreserveConfigCasing() {
        let headers = ["content-type": "application/json"]
        let allowlist = ["Content-Type"]
        let result = NetworkCaptureRule.filterHeaders(headers, allowlist: allowlist)
        XCTAssertEqual(result["Content-Type"], "application/json",
                       "Comparison case-insensitive; output key must be config key (Content-Type)")
    }

    func testFilterHeaders_emptyAllowlist_returnsEmpty() {
        let headers = ["Content-Type": "application/json"]
        let result = NetworkCaptureRule.filterHeaders(headers, allowlist: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterHeaders_emptyHeaders_returnsEmpty() {
        let result = NetworkCaptureRule.filterHeaders([:], allowlist: ["Content-Type"])
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterHeaders_multiple_onlyAllowlistedIncluded() {
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer t", "Accept": "application/json"]
        let allowlist = ["Content-Type", "Accept"]
        let result = NetworkCaptureRule.filterHeaders(headers, allowlist: allowlist)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["Content-Type"], "application/json")
        XCTAssertEqual(result["Accept"], "application/json")
        XCTAssertNil(result["Authorization"])
    }

    // MARK: - stringifyBody (CX-33234)

    func testStringifyBody_applicationJson_returnsCompactJson() {
        let data = "{\"a\":1,\"b\":2}".data(using: .utf8)!
        let result = NetworkCaptureRule.stringifyBody(data: data, contentType: "application/json")
        XCTAssertEqual(result, "{\"a\":1,\"b\":2}")
    }

    /// Regression: stringifyJSON must not canonicalize key order (no .sortedKeys); original key order retained.
    func testStringifyBody_applicationJson_preservesKeyOrder() {
        let data = "{\"b\":2,\"a\":1}".data(using: .utf8)!
        let result = NetworkCaptureRule.stringifyBody(data: data, contentType: "application/json")
        XCTAssertEqual(result, "{\"b\":2,\"a\":1}", "Key order should be preserved")
    }

    func testStringifyBody_applicationJsonWithCharset_returnsCompactJson() {
        let data = "{\"x\":\"hello\"}".data(using: .utf8)!
        let result = NetworkCaptureRule.stringifyBody(data: data, contentType: "application/json; charset=utf-8")
        XCTAssertEqual(result, "{\"x\":\"hello\"}")
    }

    /// Regression: top-level JSON fragments must be accepted (parse uses .fragmentsAllowed), not rejected as invalid JSON.
    func testStringifyBody_applicationJson_topLevelFragments_preserved() {
        let cases: [(String, String)] = [
            ("true", "true"),
            ("123", "123"),
            ("\"ok\"", "\"ok\""),
            ("null", "null"),
        ]
        for (input, expected) in cases {
            let data = input.data(using: .utf8)!
            let result = NetworkCaptureRule.stringifyBody(data: data, contentType: "application/json")
            XCTAssertEqual(result, expected, "Fragment '\(input)' should be preserved")
        }
    }

    func testStringifyBody_textPlain_returnsUtf8String() {
        let data = "Hello, world".data(using: .utf8)!
        let result = NetworkCaptureRule.stringifyBody(data: data, contentType: "text/plain")
        XCTAssertEqual(result, "Hello, world")
    }

    func testStringifyBody_textHtml_returnsUtf8String() {
        let data = "<html></html>".data(using: .utf8)!
        let result = NetworkCaptureRule.stringifyBody(data: data, contentType: "text/html")
        XCTAssertEqual(result, "<html></html>")
    }

    func testStringifyBody_unsupportedType_returnsNil() {
        let data = Data([0x00, 0x01, 0xFF])
        XCTAssertNil(NetworkCaptureRule.stringifyBody(data: data, contentType: "application/octet-stream"))
        XCTAssertNil(NetworkCaptureRule.stringifyBody(data: data, contentType: "image/png"))
        XCTAssertNil(NetworkCaptureRule.stringifyBody(data: data, contentType: nil))
    }

    func testStringifyBody_over1024Characters_returnsNil() {
        let long = String(repeating: "x", count: 1025)
        let data = long.data(using: .utf8)!
        let result = NetworkCaptureRule.stringifyBody(data: data, contentType: "text/plain")
        XCTAssertNil(result)
    }

    func testStringifyBody_exactly1024Characters_returnsString() {
        let exact = String(repeating: "a", count: 1024)
        let data = exact.data(using: .utf8)!
        let result = NetworkCaptureRule.stringifyBody(data: data, contentType: "text/plain")
        XCTAssertEqual(result?.count, 1024)
        XCTAssertEqual(result, exact)
    }

    /// Empty body: JSON is invalid so returns nil; text/plain decodes to empty string (CX-33237).
    func testStringifyBody_emptyBodyData() {
        let empty = Data()
        XCTAssertNil(NetworkCaptureRule.stringifyBody(data: empty, contentType: "application/json"),
                    "Empty data is not valid JSON — must return nil")
        XCTAssertEqual(NetworkCaptureRule.stringifyBody(data: empty, contentType: "text/plain"), "",
                       "Empty UTF-8 data with text/plain must return empty string")
    }

    // MARK: - readRequestBody (CX-33235)

    func testReadRequestBody_httpBody_returnsBodyAndSameRequest() throws {
        let body = "{\"foo\":1}".data(using: .utf8)!
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/post")))
        request.httpMethod = "POST"
        request.httpBody = body
        let (data, requestForSending) = NetworkCaptureRule.readRequestBody(from: request)
        XCTAssertEqual(data, body)
        XCTAssertTrue(requestForSending.httpBody == body)
        XCTAssertNil(requestForSending.httpBodyStream)
    }

    func testReadRequestBody_httpBodyStream_returnsNilDataAndOriginalRequestUnchanged() throws {
        let body = "streamed body".data(using: .utf8)!
        let stream = InputStream(data: body)
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/upload")))
        request.httpMethod = "POST"
        request.httpBodyStream = stream
        let (data, requestForSending) = NetworkCaptureRule.readRequestBody(from: request)
        XCTAssertNil(data, "Stream body is not captured so the sending request is not mutated")
        XCTAssertNil(requestForSending.httpBody)
        XCTAssertTrue(requestForSending.httpBodyStream === stream, "Original stream must be preserved for full upload")
    }

    func testReadRequestBody_bothNil_returnsNilAndSameRequest() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/get")))
        request.httpMethod = "GET"
        let (data, requestForSending) = NetworkCaptureRule.readRequestBody(from: request)
        XCTAssertNil(data)
        XCTAssertNil(requestForSending.httpBody)
        XCTAssertNil(requestForSending.httpBodyStream)
    }

    // MARK: - Mutual exclusivity
    // Enforced at compile time by the private Matcher enum — each init path sets exactly one
    // case, so no runtime white-box tests are needed here.

    // MARK: - Helpers

    private func makeOptions() -> CoralogixExporterOptions {
        CoralogixExporterOptions(coralogixDomain: .EU2,
                                 environment: "test",
                                 application: "TestApp",
                                 version: "1.0.0",
                                 publicKey: "fake-key")
    }
}
