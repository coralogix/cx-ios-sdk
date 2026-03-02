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
