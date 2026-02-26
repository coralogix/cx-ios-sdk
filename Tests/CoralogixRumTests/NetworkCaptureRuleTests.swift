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

    func testMatches_exactSubstring_returnsTrue() {
        let rule = NetworkCaptureRule(url: "api.example.com")
        XCTAssertTrue(rule.matches(URL(string: "https://api.example.com/users")!))
    }

    func testMatches_substring_caseInsensitive_returnsTrue() {
        let rule = NetworkCaptureRule(url: "API.EXAMPLE.COM")
        XCTAssertTrue(rule.matches(URL(string: "https://api.example.com/users")!))
    }

    func testMatches_noSubstringMatch_returnsFalse() {
        let rule = NetworkCaptureRule(url: "other.com")
        XCTAssertFalse(rule.matches(URL(string: "https://api.example.com/users")!))
    }

    // MARK: - matches(_:) — regex init

    func testMatches_regex_matchingPattern_returnsTrue() throws {
        let pattern = try NSRegularExpression(pattern: "api\\.example\\.com/users/\\d+")
        let rule = NetworkCaptureRule(urlPattern: pattern)
        XCTAssertTrue(rule.matches(URL(string: "https://api.example.com/users/42")!))
    }

    func testMatches_regex_nonMatchingPattern_returnsFalse() throws {
        let pattern = try NSRegularExpression(pattern: "api\\.example\\.com/orders/\\d+")
        let rule = NetworkCaptureRule(urlPattern: pattern)
        XCTAssertFalse(rule.matches(URL(string: "https://api.example.com/users/42")!))
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

    func testOptions_networkExtraConfig_storesRules() {
        let rule = NetworkCaptureRule(url: "api.example.com",
                                     reqHeaders: ["Authorization"],
                                     collectResPayload: true)
        var options = makeOptions()
        options.networkExtraConfig = [rule]
        XCTAssertEqual(options.networkExtraConfig?.count, 1)
        XCTAssertEqual(options.networkExtraConfig?.first?.url, "api.example.com")
        XCTAssertEqual(options.networkExtraConfig?.first?.reqHeaders, ["Authorization"])
        XCTAssertEqual(options.networkExtraConfig?.first?.collectResPayload, true)
    }

    // MARK: - Mutual exclusivity

    func testStringInit_urlPatternIsNil() {
        let rule = NetworkCaptureRule(url: "api.example.com")
        XCTAssertNil(rule.urlPattern)
    }

    func testRegexInit_urlIsEmpty() throws {
        let pattern = try NSRegularExpression(pattern: ".*")
        let rule = NetworkCaptureRule(urlPattern: pattern)
        XCTAssertEqual(rule.url, "")
        XCTAssertNotNil(rule.urlPattern)
    }

    // MARK: - Helpers

    private func makeOptions() -> CoralogixExporterOptions {
        CoralogixExporterOptions(coralogixDomain: .EU2,
                                 environment: "test",
                                 application: "TestApp",
                                 version: "1.0.0",
                                 publicKey: "fake-key")
    }
}
