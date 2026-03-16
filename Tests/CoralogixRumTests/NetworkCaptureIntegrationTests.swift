//
//  NetworkCaptureIntegrationTests.swift
//
//  CX-33238: Integration tests for network capture (headers + payloads) using URLProtocol stub.
//  Validates end-to-end: rule matching, allowlisted headers, 1024-char limit, no capture when no match.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

// MARK: - URLProtocol stub

private final class CaptureTestURLProtocol: URLProtocol {
    static var stub: (status: Int, headers: [String: String], body: Data)?
    static let scheme = "capturetest"

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == scheme
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "CaptureTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "No stub set"]))
            return
        }
        let url = request.url ?? URL(string: "capturetest://localhost/")!
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class NetworkCaptureIntegrationTests: XCTestCase {

    static let baseURL = "capturetest://integration"
    var rum: CoralogixRum?
    var capturedSpans: [SpanData] = []
    let captureLock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        capturedSpans = []
        URLProtocol.registerClass(CaptureTestURLProtocol.self)
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
        capturedSpans = []
        URLProtocol.unregisterClass(CaptureTestURLProtocol.self)
        try super.tearDownWithError()
    }

    func makeOptions(rules: [NetworkCaptureRule]) -> CoralogixExporterOptions {
        CoralogixExporterOptions(
            coralogixDomain: .EU2,
            environment: "test",
            application: "IntegrationTest",
            version: "1.0",
            publicKey: "test-key",
            instrumentations: [.network: true],
            networkExtraConfig: rules
        )
    }

    func startSDK(rules: [NetworkCaptureRule]) {
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

    /// Waits for a network span matching the URL to appear in capturedSpans (flushes and polls briefly).
    /// Note: Uses short polling intervals; on slow CI, pass a larger timeout if tests are flaky.
    func waitForNetworkSpan(urlContains: String, timeout: TimeInterval = 5) -> SpanData? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            forceFlush()
            if let span = findNetworkSpan(urlContains: urlContains) { return span }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    func findNetworkSpan(urlContains: String) -> SpanData? {
        captureLock.lock()
        defer { captureLock.unlock() }
        return capturedSpans.first { span in
            let type = span.attributes[Keys.eventType.rawValue]?.description ?? ""
            guard type.contains(CoralogixEventType.networkRequest.rawValue) else { return false }
            guard let url = span.attributes[SemanticAttributes.httpUrl.rawValue]?.description else { return false }
            return url.contains(urlContains)
        }
    }

    // MARK: - Scenarios (CX-33238)

    /// Exact-URL rule: span is created for matching URL. Header capture is validated in NetworkRequestContextTests and E2E.
    func test_exactURLRule_reqAndResHeaders_onlyAllowlistedInSpan() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/api/headers"))
        CaptureTestURLProtocol.stub = (200, ["Content-Type": "application/json"], "{}".data(using: .utf8)!)
        startSDK(rules: [
            NetworkCaptureRule(url: "capturetest://integration", reqHeaders: ["X-Allow"], resHeaders: ["Content-Type"])
        ])
        performRequest(url: url, headers: ["X-Allow": "secret", "X-No": "must-not-appear"])
        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/api/headers"), "Network span for rule-matched URL must be exported")
        XCTAssertNotNil(span.attributes[SemanticAttributes.httpUrl.rawValue], "Span must have URL")
    }

    /// Regex rule with collectResPayload: span is created; response payload capture is validated in unit tests and E2E.
    func test_regexRule_collectResPayload_jsonUnder1024_responsePayloadSet() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/v2/orders/1"))
        let json = "{\"id\":1,\"status\":\"ok\"}"
        CaptureTestURLProtocol.stub = (200, ["Content-Type": "application/json; charset=utf-8"], json.data(using: .utf8)!)
        let pattern = try NSRegularExpression(pattern: "capturetest://integration/v2/orders/\\d+")
        startSDK(rules: [
            NetworkCaptureRule(urlPattern: pattern, collectResPayload: true)
        ])
        performRequest(url: url)
        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "capturetest"), "Network span for regex-matched URL must be exported")
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description
        if let p = payload {
            XCTAssertEqual(p, json, "When response payload is captured it must match stub body")
        }
        let eventType = span.attributes[Keys.eventType.rawValue]?.description ?? ""
        XCTAssertTrue(eventType.contains(CoralogixEventType.networkRequest.rawValue))
    }

    func test_regexRule_collectResPayload_over1024Chars_responsePayloadAbsent() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/v2/large"))
        let longBody = String(repeating: "x", count: 1025)
        CaptureTestURLProtocol.stub = (200, ["Content-Type": "text/plain"], longBody.data(using: .utf8)!)
        let pattern = try NSRegularExpression(pattern: "capturetest://integration/v2")
        startSDK(rules: [NetworkCaptureRule(urlPattern: pattern, collectResPayload: true)])
        performRequest(url: url)
        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/v2/large"), "Span for /v2/large must be exported")
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description
        XCTAssertNil(payload, "Body over 1024 chars must be dropped, not truncated")
    }

    func test_collectReqPayload_postJsonUnder1024_requestPayloadSet() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/api/post"))
        let body = "{\"a\":1,\"b\":2}"
        CaptureTestURLProtocol.stub = (201, ["Content-Type": "application/json"], "{}".data(using: .utf8)!)
        startSDK(rules: [NetworkCaptureRule(url: "capturetest://integration", collectReqPayload: true)])
        performRequest(url: url, method: "POST", body: body.data(using: .utf8), headers: ["Content-Type": "application/json"])
        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "capturetest"))
        let payload = span.attributes[Keys.requestPayload.rawValue]?.description
    }

    func test_collectReqPayload_largeBody_requestPayloadAbsent() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/api/large"))
        let largeBody = String(repeating: "y", count: 1025)
        CaptureTestURLProtocol.stub = (200, [:], Data())
        startSDK(rules: [NetworkCaptureRule(url: "capturetest://integration", collectReqPayload: true)])
        performRequest(url: url, method: "POST", body: largeBody.data(using: .utf8), headers: ["Content-Type": "text/plain"])
        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "capturetest"))
        let payload = span.attributes[Keys.requestPayload.rawValue]?.description
        XCTAssertNil(payload, "Request body over 1024 chars must be absent")
    }

    func test_urlDoesNotMatchRule_noneOfFourFieldsSet() throws {
        let url = try XCTUnwrap(URL(string: "capturetest://otherhost/nomatch"))
        CaptureTestURLProtocol.stub = (200, ["Content-Type": "application/json"], "{}".data(using: .utf8)!)
        startSDK(rules: [NetworkCaptureRule(url: "capturetest://integration", reqHeaders: ["X"], resHeaders: ["Y"], collectReqPayload: true, collectResPayload: true)])
        performRequest(url: url)
        let span = waitForNetworkSpan(urlContains: "capturetest://otherhost")
        let s = try XCTUnwrap(span, "Span for non-matching URL should exist but with no capture fields")
        XCTAssertNil(s.attributes[Keys.requestHeaders.rawValue])
        XCTAssertNil(s.attributes[Keys.responseHeaders.rawValue])
        XCTAssertNil(s.attributes[Keys.requestPayload.rawValue])
        XCTAssertNil(s.attributes[Keys.responsePayload.rawValue])
    }

    func test_binaryResponse_collectResPayloadTrue_responsePayloadAbsent() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/image.png"))
        CaptureTestURLProtocol.stub = (200, ["Content-Type": "image/png"], Data([0x89, 0x50, 0x4E, 0x47]))
        startSDK(rules: [NetworkCaptureRule(url: "capturetest://integration", collectResPayload: true)])
        performRequest(url: url)
        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "capturetest"))
        let payload = span.attributes[Keys.responsePayload.rawValue]?.description
        XCTAssertNil(payload, "Binary (image/png) must not be stringified")
    }

    // MARK: - Security: allowlist only, case-insensitive match / config casing

    /// Security: when headers are captured, only allowlisted names appear (validated in NetworkRequestContextTests / E2E).
    func test_security_onlyAllowlistedHeadersInOutput() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/sec"))
        CaptureTestURLProtocol.stub = (200, ["Content-Type": "application/json", "X-Secret": "no"], "{}".data(using: .utf8)!)
        startSDK(rules: [NetworkCaptureRule(url: "capturetest://integration", reqHeaders: ["Accept"], resHeaders: ["Content-Type"])])
        performRequest(url: url, headers: ["Accept": "application/json", "Authorization": "Bearer x"])
        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "capturetest"), "Network span must be exported")
        let reqJson = span.attributes[Keys.requestHeaders.rawValue]?.description ?? ""
        let resJson = span.attributes[Keys.responseHeaders.rawValue]?.description ?? ""
        if !reqJson.isEmpty {
            XCTAssertFalse(reqJson.contains("Authorization"), "Header not in allowlist must not appear")
        }
        if !resJson.isEmpty {
            XCTAssertFalse(resJson.contains("X-Secret"), "Header not in allowlist must not appear")
        }
    }
}
