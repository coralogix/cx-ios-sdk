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

    func testResolveConfigForUrl_firstMatchWins_returnsFirstMatchingRule() {
        let firstRule  = NetworkCaptureRule(url: "example.com", reqHeaders: ["X-First"])
        let secondRule = NetworkCaptureRule(url: "example.com", reqHeaders: ["X-Second"])
        let result = resolveConfigForUrl("https://api.example.com/users", configs: [firstRule, secondRule])
        XCTAssertEqual(result?.reqHeaders, ["X-First"],
                       "First matching rule should win; second rule must not be returned")
    }

    func testResolveConfigForUrl_firstMatchWins_nonMatchingRuleBeforeMatchingRule() throws {
        let nonMatching = NetworkCaptureRule(url: "other.com")
        let matching    = NetworkCaptureRule(url: "example.com", collectReqPayload: true)
        let result = try XCTUnwrap(resolveConfigForUrl("https://api.example.com/users", configs: [nonMatching, matching]))
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
