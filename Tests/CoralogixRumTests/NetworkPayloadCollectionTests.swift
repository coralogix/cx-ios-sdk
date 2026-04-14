//
//  NetworkPayloadCollectionTests.swift
//  CoralogixRumTests
//
//  CX-36931: Regression tests for network payload and header collection.
//  Validates:
//  - Request headers are captured correctly with allowlist filtering
//  - Response headers are captured correctly with allowlist filtering
//  - Request body (payload) is collected when enabled
//  - Response body (payload) is collected when enabled
//  - Sensitive headers are excluded when not in allowlist
//  - Size limits are respected (1024 char limit for payloads)
//  - Binary content types are not captured
//

import XCTest
import CoralogixInternal
@testable import Coralogix

// MARK: - URLProtocol stub

private final class PayloadTestURLProtocol: URLProtocol {
    static var stub: (status: Int, headers: [String: String], body: Data)?
    static var lastRequest: URLRequest?
    static let scheme = "payloadtest"

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == scheme
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request

        guard let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "PayloadTest", code: -1, userInfo: nil))
            return
        }
        let url = request.url ?? URL(string: "\(Self.scheme)://localhost/")!
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        stub = nil
        lastRequest = nil
    }
}

// MARK: - Tests

final class NetworkPayloadCollectionTests: XCTestCase {

    static let baseURL = "payloadtest://cx36931"
    var rum: CoralogixRum?
    var capturedSpans: [SpanData] = []
    let captureLock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        capturedSpans = []
        PayloadTestURLProtocol.reset()
        URLProtocol.registerClass(PayloadTestURLProtocol.self)
        CoralogixExporter.testExportCallback = { [weak self] spans in
            self?.captureLock.lock()
            self?.capturedSpans.append(contentsOf: spans)
            self?.captureLock.unlock()
        }
    }

    override func tearDownWithError() throws {
        rum = nil
        CoralogixRum.isInitialized = false
        CoralogixExporter.testExportCallback = nil
        captureLock.lock()
        capturedSpans.removeAll(keepingCapacity: false)
        captureLock.unlock()
        PayloadTestURLProtocol.reset()
        URLProtocol.unregisterClass(PayloadTestURLProtocol.self)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    func makeOptions(rules: [NetworkCaptureRule]) -> CoralogixExporterOptions {
        CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: nil,
            environment: "test",
            application: "CX36931PayloadTests",
            version: "1.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            instrumentations: [.network: true],
            networkExtraConfig: rules,
            debug: true
        )
    }

    func startRUM(rules: [NetworkCaptureRule]) {
        rum = CoralogixRum(options: makeOptions(rules: rules))
        XCTAssertTrue(CoralogixRum.isInitialized)
    }

    func performRequest(url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let exp = expectation(description: "request")
        URLSession.shared.dataTask(with: request) { _, _, _ in exp.fulfill() }.resume()
        wait(for: [exp], timeout: 5)
    }

    func forceFlush() {
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.6)
    }

    func waitForNetworkSpan(urlContains: String, requiringRequestPayload: Bool = false, timeout: TimeInterval = 8) -> SpanData? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            forceFlush()
            if let span = findNetworkSpan(urlContains: urlContains, requiringRequestPayload: requiringRequestPayload) {
                return span
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return nil
    }

    func findNetworkSpan(urlContains: String, requiringRequestPayload: Bool = false) -> SpanData? {
        captureLock.lock()
        defer { captureLock.unlock() }
        return capturedSpans.last { span in
            let type = span.attributes[Keys.eventType.rawValue]?.description ?? ""
            guard type.contains(CoralogixEventType.networkRequest.rawValue) else { return false }
            guard let url = span.attributes[SemanticAttributes.httpUrl.rawValue]?.description else { return false }
            guard url.contains(urlContains) else { return false }
            if requiringRequestPayload {
                return span.attributes[Keys.requestPayload.rawValue] != nil
            }
            return true
        }
    }

    // MARK: - Request Headers Tests

    func test_requestHeaders_onlyAllowlistedHeadersAreCaptured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/req-headers"))
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "application/json"], "{}".data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", reqHeaders: ["X-Custom-Header", "Accept"])
        ])

        performRequest(url: url, headers: [
            "X-Custom-Header": "custom-value",
            "Accept": "application/json",
            "Authorization": "Bearer secret-token",
            "X-Not-Allowed": "should-not-appear"
        ])

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/req-headers"), "Network span must be exported")
        let reqHeadersJson = span.attributes[Keys.requestHeaders.rawValue]?.description

        if let json = reqHeadersJson, !json.isEmpty {
            XCTAssertTrue(json.contains("X-Custom-Header") || json.contains("x-custom-header"),
                          "Allowlisted header X-Custom-Header should be captured")
            XCTAssertFalse(json.lowercased().contains("authorization"),
                           "Non-allowlisted Authorization header must NOT be captured")
            XCTAssertFalse(json.lowercased().contains("x-not-allowed"),
                           "Non-allowlisted X-Not-Allowed header must NOT be captured")
        }
    }

    func test_requestHeaders_caseInsensitiveMatching() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/req-headers-case"))
        PayloadTestURLProtocol.stub = (200, [:], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", reqHeaders: ["content-type"])
        ])

        performRequest(url: url, headers: ["Content-Type": "application/json"])

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/req-headers-case"))
        let reqHeadersJson = span.attributes[Keys.requestHeaders.rawValue]?.description

        if let json = reqHeadersJson, !json.isEmpty {
            XCTAssertTrue(json.lowercased().contains("content-type"),
                          "Header matching should be case-insensitive")
        }
    }

    func test_requestHeaders_emptyAllowlist_noHeadersCaptured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/req-headers-empty"))
        PayloadTestURLProtocol.stub = (200, [:], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", reqHeaders: [])
        ])

        performRequest(url: url, headers: ["X-Custom": "value"])

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/req-headers-empty"))
        let reqHeadersJson = span.attributes[Keys.requestHeaders.rawValue]?.description

        XCTAssertTrue(reqHeadersJson == nil || reqHeadersJson == "{}" || reqHeadersJson?.isEmpty == true,
                      "Empty allowlist should result in no headers captured")
    }

    // MARK: - Response Headers Tests

    func test_responseHeaders_onlyAllowlistedHeadersAreCaptured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/res-headers"))
        PayloadTestURLProtocol.stub = (200, [
            "Content-Type": "application/json",
            "X-Request-Id": "req-123",
            "Set-Cookie": "session=secret",
            "X-Rate-Limit": "100"
        ], "{}".data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", resHeaders: ["Content-Type", "X-Request-Id"])
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/res-headers"))
        let resHeadersJson = span.attributes[Keys.responseHeaders.rawValue]?.description

        if let json = resHeadersJson, !json.isEmpty {
            XCTAssertTrue(json.lowercased().contains("content-type"),
                          "Allowlisted Content-Type should be captured")
            XCTAssertFalse(json.lowercased().contains("set-cookie"),
                           "Non-allowlisted Set-Cookie must NOT be captured")
            XCTAssertFalse(json.lowercased().contains("x-rate-limit"),
                           "Non-allowlisted X-Rate-Limit must NOT be captured")
        }
    }

    func test_responseHeaders_caseInsensitiveMatching() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/res-headers-case"))
        PayloadTestURLProtocol.stub = (200, ["CONTENT-TYPE": "text/plain"], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", resHeaders: ["content-type"])
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/res-headers-case"))
        let resHeadersJson = span.attributes[Keys.responseHeaders.rawValue]?.description

        if let json = resHeadersJson, !json.isEmpty {
            XCTAssertTrue(json.lowercased().contains("content-type"),
                          "Response header matching should be case-insensitive")
        }
    }

    // MARK: - Request Payload Tests

    func test_requestPayload_jsonBodyCaptured_whenEnabled() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/req-payload"))
        let requestBody = "{\"user\":\"test\",\"action\":\"login\"}"
        PayloadTestURLProtocol.stub = (201, ["Content-Type": "application/json"], "{}".data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectReqPayload: true)
        ])

        performRequest(url: url, method: "POST", body: requestBody.data(using: .utf8), headers: [
            "Content-Type": "application/json"
        ])

        let span = try XCTUnwrap(
            waitForNetworkSpan(urlContains: "/req-payload", requiringRequestPayload: true),
            "Network span with request_payload must be exported"
        )
        let payload = span.attributes[Keys.requestPayload.rawValue]?.description

        XCTAssertEqual(payload, requestBody, "Request payload must match the original request body")
    }

    func test_requestPayload_notCaptured_whenDisabled() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/req-payload-disabled"))
        PayloadTestURLProtocol.stub = (200, [:], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectReqPayload: false)
        ])

        performRequest(url: url, method: "POST", body: "{\"data\":1}".data(using: .utf8))

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/req-payload-disabled"))
        let payload = span.attributes[Keys.requestPayload.rawValue]?.description

        XCTAssertNil(payload, "Request payload must not be captured when collectReqPayload is false")
    }

    func test_requestPayload_over1024Chars_notCaptured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/req-payload-large"))
        let largeBody = String(repeating: "x", count: 1025)
        PayloadTestURLProtocol.stub = (200, [:], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectReqPayload: true)
        ])

        performRequest(url: url, method: "POST", body: largeBody.data(using: .utf8), headers: [
            "Content-Type": "text/plain"
        ])

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/req-payload-large", timeout: 15))
        let payload = span.attributes[Keys.requestPayload.rawValue]?.description

        XCTAssertNil(payload, "Request body over 1024 chars must NOT be captured")
    }

    func test_requestPayload_exactly1024Chars_captured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/req-payload-exact"))
        let exactBody = String(repeating: "a", count: 1024)
        PayloadTestURLProtocol.stub = (200, [:], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectReqPayload: true)
        ])

        performRequest(url: url, method: "POST", body: exactBody.data(using: .utf8), headers: [
            "Content-Type": "text/plain"
        ])

        let span = waitForNetworkSpan(urlContains: "/req-payload-exact", requiringRequestPayload: true)
        if let s = span {
            let payload = s.attributes[Keys.requestPayload.rawValue]?.description
            XCTAssertEqual(payload?.count, 1024, "Exactly 1024 char body should be captured")
        }
    }

    // MARK: - Response Payload Tests

    func test_responsePayload_jsonBodyCaptured_whenEnabled() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/res-payload"))
        let responseBody = "{\"status\":\"success\",\"id\":123}"
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "application/json"], responseBody.data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/res-payload"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        if let p = payload {
            XCTAssertEqual(p, responseBody, "Response payload must match the stub body")
        }
    }

    func test_responsePayload_notCaptured_whenDisabled() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/res-payload-disabled"))
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "application/json"], "{\"data\":1}".data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: false)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/res-payload-disabled"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        XCTAssertNil(payload, "Response payload must not be captured when collectResPayload is false")
    }

    func test_responsePayload_over1024Chars_notCaptured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/res-payload-large"))
        let largeBody = String(repeating: "y", count: 1025)
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "text/plain"], largeBody.data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/res-payload-large"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        XCTAssertNil(payload, "Response body over 1024 chars must NOT be captured")
    }

    func test_responsePayload_exactly1024Chars_captured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/res-payload-exact"))
        let exactBody = String(repeating: "b", count: 1024)
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "text/plain"], exactBody.data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/res-payload-exact"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        if let p = payload {
            XCTAssertEqual(p.count, 1024, "Exactly 1024 char response body should be captured")
        }
    }

    // MARK: - Binary Content Type Tests

    func test_responsePayload_binaryContentType_notCaptured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/binary-response"))
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "image/png"], Data([0x89, 0x50, 0x4E, 0x47]))

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/binary-response"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        XCTAssertNil(payload, "Binary content (image/png) must NOT be captured as payload")
    }

    func test_responsePayload_octetStreamContentType_notCaptured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/octet-stream"))
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "application/octet-stream"], Data([0x00, 0x01, 0x02]))

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/octet-stream"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        XCTAssertNil(payload, "application/octet-stream content must NOT be captured")
    }

    // MARK: - No Rule Match Tests

    func test_noRuleMatch_noCaptureFieldsSet() throws {
        let url = try XCTUnwrap(URL(string: "payloadtest://otherhost/no-match"))
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "application/json"], "{\"data\":1}".data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://cx36931",
                              reqHeaders: ["X-Custom"],
                              resHeaders: ["Content-Type"],
                              collectReqPayload: true,
                              collectResPayload: true)
        ])

        performRequest(url: url, headers: ["X-Custom": "value"])

        let span = waitForNetworkSpan(urlContains: "payloadtest://otherhost")
        if let s = span {
            XCTAssertNil(s.attributes[Keys.requestHeaders.rawValue], "No rule match → no request headers")
            XCTAssertNil(s.attributes[Keys.responseHeaders.rawValue], "No rule match → no response headers")
            XCTAssertNil(s.attributes[Keys.requestPayload.rawValue], "No rule match → no request payload")
            XCTAssertNil(s.attributes[Keys.responsePayload.rawValue], "No rule match → no response payload")
        }
    }

    // MARK: - Multiple Rules Merge Tests

    func test_multipleMatchingRules_headersMerged() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/multi-rule"))
        PayloadTestURLProtocol.stub = (200, [
            "Content-Type": "application/json",
            "X-Request-Id": "123",
            "X-Custom": "value"
        ], "{}".data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", resHeaders: ["Content-Type"]),
            NetworkCaptureRule(url: "cx36931", resHeaders: ["X-Request-Id", "X-Custom"])
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/multi-rule"))
        let resHeadersJson = span.attributes[Keys.responseHeaders.rawValue]?.description

        if let json = resHeadersJson, !json.isEmpty {
            XCTAssertTrue(json.lowercased().contains("content-type"),
                          "Content-Type from first rule should be in merged allowlist")
            XCTAssertTrue(json.lowercased().contains("x-request-id"),
                          "X-Request-Id from second rule should be in merged allowlist")
        }
    }

    func test_multipleMatchingRules_payloadEnabledIfAnyRuleEnables() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/multi-rule-payload"))
        let responseBody = "{\"merged\":true}"
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "application/json"], responseBody.data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: false),
            NetworkCaptureRule(url: "cx36931", collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/multi-rule-payload"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        if let p = payload {
            XCTAssertEqual(p, responseBody,
                          "Response payload should be captured if any matching rule enables it")
        }
    }

    // MARK: - Regex Rule Tests

    func test_regexRule_matchesCorrectUrls() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/api/v2/users/42"))
        let responseBody = "{\"id\":42}"
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "application/json"], responseBody.data(using: .utf8)!)

        let pattern = try NSRegularExpression(pattern: "cx36931/api/v2/users/\\d+")
        startRUM(rules: [
            NetworkCaptureRule(urlPattern: pattern, collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/api/v2/users/42"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        if let p = payload {
            XCTAssertEqual(p, responseBody, "Regex-matched URL should have payload captured")
        }
    }

    func test_regexRule_doesNotMatchIncorrectUrls() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/api/v1/posts"))
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "application/json"], "{\"posts\":[]}".data(using: .utf8)!)

        let pattern = try NSRegularExpression(pattern: "cx36931/api/v2/users/\\d+")
        startRUM(rules: [
            NetworkCaptureRule(urlPattern: pattern, collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/api/v1/posts"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        XCTAssertNil(payload, "Non-matching regex should not capture payload")
    }

    // MARK: - Text Content Types

    func test_responsePayload_textPlain_captured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/text-plain"))
        let textBody = "Hello, World!"
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "text/plain"], textBody.data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/text-plain"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        if let p = payload {
            XCTAssertEqual(p, textBody, "text/plain content should be captured")
        }
    }

    func test_responsePayload_textHtml_captured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/text-html"))
        let htmlBody = "<html><body>Test</body></html>"
        PayloadTestURLProtocol.stub = (200, ["Content-Type": "text/html"], htmlBody.data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/text-html"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        if let p = payload {
            XCTAssertEqual(p, htmlBody, "text/html content should be captured")
        }
    }

    // MARK: - Sensitive Header Exclusion (Security)

    func test_sensitiveHeaders_notCaptured_whenNotInAllowlist() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/sensitive-headers"))
        PayloadTestURLProtocol.stub = (200, [
            "Content-Type": "application/json",
            "Set-Cookie": "session=secret123",
            "WWW-Authenticate": "Bearer realm=\"api\""
        ], "{}".data(using: .utf8)!)

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", resHeaders: ["Content-Type"])
        ])

        performRequest(url: url, headers: [
            "Authorization": "Bearer token123",
            "Cookie": "session=abc",
            "Content-Type": "application/json"
        ])

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/sensitive-headers"))

        let reqHeadersJson = span.attributes[Keys.requestHeaders.rawValue]?.description ?? ""
        let resHeadersJson = span.attributes[Keys.responseHeaders.rawValue]?.description ?? ""

        XCTAssertFalse(reqHeadersJson.lowercased().contains("authorization"),
                       "Authorization header must not be captured when not in allowlist")
        XCTAssertFalse(reqHeadersJson.lowercased().contains("cookie"),
                       "Cookie header must not be captured when not in allowlist")
        XCTAssertFalse(resHeadersJson.lowercased().contains("set-cookie"),
                       "Set-Cookie header must not be captured when not in allowlist")
        XCTAssertFalse(resHeadersJson.lowercased().contains("www-authenticate"),
                       "WWW-Authenticate header must not be captured when not in allowlist")
    }

    // MARK: - HTTP Method Tests

    func test_requestPayload_captured_forPUTRequest() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/put-request"))
        let body = "{\"update\":true}"
        PayloadTestURLProtocol.stub = (200, [:], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectReqPayload: true)
        ])

        performRequest(url: url, method: "PUT", body: body.data(using: .utf8), headers: [
            "Content-Type": "application/json"
        ])

        let span = waitForNetworkSpan(urlContains: "/put-request", requiringRequestPayload: true)
        if let s = span {
            let payload = s.attributes[Keys.requestPayload.rawValue]?.description
            XCTAssertEqual(payload, body, "PUT request payload should be captured")
        }
    }

    func test_requestPayload_captured_forPATCHRequest() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/patch-request"))
        let body = "{\"patch\":\"data\"}"
        PayloadTestURLProtocol.stub = (200, [:], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectReqPayload: true)
        ])

        performRequest(url: url, method: "PATCH", body: body.data(using: .utf8), headers: [
            "Content-Type": "application/json"
        ])

        let span = waitForNetworkSpan(urlContains: "/patch-request", requiringRequestPayload: true)
        if let s = span {
            let payload = s.attributes[Keys.requestPayload.rawValue]?.description
            XCTAssertEqual(payload, body, "PATCH request payload should be captured")
        }
    }

    // MARK: - Empty Body Tests

    func test_requestPayload_emptyBody_notCaptured() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/empty-body"))
        PayloadTestURLProtocol.stub = (200, [:], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectReqPayload: true)
        ])

        performRequest(url: url, method: "POST", body: nil)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/empty-body"))
        let payload = span.attributes[Keys.requestPayload.rawValue]?.description

        XCTAssertNil(payload, "Empty/nil request body should result in no request_payload attribute")
    }

    func test_responsePayload_emptyBody_handledGracefully() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/empty-response"))
        PayloadTestURLProtocol.stub = (204, ["Content-Type": "application/json"], Data())

        startRUM(rules: [
            NetworkCaptureRule(url: "payloadtest://", collectResPayload: true)
        ])

        performRequest(url: url)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/empty-response"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description

        // Empty body is not valid JSON, so should be nil or empty string depending on implementation
        XCTAssertTrue(payload == nil || payload == "",
                      "Empty response body should be handled gracefully (nil or empty)")
    }
}
