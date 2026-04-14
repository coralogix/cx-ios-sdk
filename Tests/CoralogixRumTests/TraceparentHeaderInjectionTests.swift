//
//  TraceparentHeaderInjectionTests.swift
//  CoralogixRumTests
//
//  CX-36931: Regression tests for traceparent header injection on outgoing HTTP requests.
//  Validates:
//  - traceparent header is correctly injected when enabled
//  - Header format is W3C spec-compliant (version-traceid-parentid-flags)
//  - Injection works for URLSession
//  - shouldAddTraceParent logic correctly blocks injection when disabled
//  - shouldAddTraceParent respects Coralogix domain exclusion
//  - shouldAddTraceParent respects allowedTracingUrls configuration
//

import XCTest
import CoralogixInternal
@testable import Coralogix

// MARK: - URLProtocol stub for capturing outgoing requests

private final class TraceparentTestURLProtocol: URLProtocol {
    static var stub: (status: Int, headers: [String: String], body: Data)?
    static var lastRequest: URLRequest?
    static var lastTraceparentHeader: String?
    static var lastTracestateHeader: String?
    static let scheme = "traceparenttest"

    private static func header(from request: URLRequest, named headerName: String) -> String? {
        guard let fields = request.allHTTPHeaderFields else { return nil }
        for (key, value) in fields where key.lowercased() == headerName.lowercased() {
            return value
        }
        return nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == scheme
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastTraceparentHeader = Self.header(from: request, named: "traceparent")
        Self.lastTracestateHeader = Self.header(from: request, named: "tracestate")

        guard let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "TraceparentTest", code: -1, userInfo: nil))
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
        lastTraceparentHeader = nil
        lastTracestateHeader = nil
    }
}

// MARK: - Tests

final class TraceparentHeaderInjectionTests: XCTestCase {

    static let baseURL = "traceparenttest://cx36931"
    var rum: CoralogixRum?
    var capturedSpans: [SpanData] = []
    let captureLock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        capturedSpans = []
        TraceparentTestURLProtocol.reset()
        URLProtocol.registerClass(TraceparentTestURLProtocol.self)
        CoralogixExporter.testExportCallback = { [weak self] spans in
            self?.captureLock.lock()
            self?.capturedSpans.append(contentsOf: spans)
            self?.captureLock.unlock()
        }
    }

    override func tearDownWithError() throws {
        rum = nil
        CoralogixRum.isInitialized = false
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        CoralogixExporter.testExportCallback = nil
        captureLock.lock()
        capturedSpans.removeAll(keepingCapacity: false)
        captureLock.unlock()
        TraceparentTestURLProtocol.reset()
        URLProtocol.unregisterClass(TraceparentTestURLProtocol.self)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    func makeOptions(
        traceParentInHeader: [String: Any]? = nil,
        coralogixDomain: CoralogixDomain = .EU2
    ) -> CoralogixExporterOptions {
        CoralogixExporterOptions(
            coralogixDomain: coralogixDomain,
            userContext: nil,
            environment: "test",
            application: "CX36931TraceparentTests",
            version: "1.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            instrumentations: [.network: true],
            traceParentInHeader: traceParentInHeader,
            debug: true
        )
    }

    func startRUM(traceParentInHeader: [String: Any]? = nil, coralogixDomain: CoralogixDomain = .EU2) {
        rum = CoralogixRum(options: makeOptions(traceParentInHeader: traceParentInHeader, coralogixDomain: coralogixDomain))
        XCTAssertTrue(CoralogixRum.isInitialized)
    }

    func performRequest(url: URL, completion: (() -> Void)? = nil) {
        let exp = expectation(description: "request")
        URLSession.shared.dataTask(with: url) { _, _, _ in
            exp.fulfill()
            completion?()
        }.resume()
        wait(for: [exp], timeout: 5)
    }

    func forceFlush() {
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - W3C Traceparent Format Validation

    /// Validates that the traceparent header follows W3C spec: `version-traceid-parentid-flags`
    /// - version: 2 lowercase hex chars (currently "00")
    /// - traceid: 32 lowercase hex chars
    /// - parentid (spanid): 16 lowercase hex chars
    /// - flags: 2 lowercase hex chars
    func validateTraceparentFormat(_ header: String) -> (isValid: Bool, version: String?, traceId: String?, spanId: String?, flags: String?) {
        let parts = header.split(separator: "-", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count == 4 else {
            return (false, nil, nil, nil, nil)
        }

        let version = parts[0]
        let traceId = parts[1]
        let spanId = parts[2]
        let flags = parts[3]

        let hexPattern = "^[0-9a-f]+$"
        let hexRegex = try? NSRegularExpression(pattern: hexPattern, options: [])

        func isValidHex(_ str: String, length: Int) -> Bool {
            guard str.count == length else { return false }
            let range = NSRange(str.startIndex..., in: str)
            return hexRegex?.firstMatch(in: str, options: [], range: range) != nil
        }

        let isVersionValid = isValidHex(version, length: 2)
        let isTraceIdValid = isValidHex(traceId, length: 32)
        let isSpanIdValid = isValidHex(spanId, length: 16)
        let isFlagsValid = isValidHex(flags, length: 2)

        let isValid = isVersionValid && isTraceIdValid && isSpanIdValid && isFlagsValid
        return (isValid, version, traceId, spanId, flags)
    }

    // MARK: - End-to-End Tests: Traceparent injection when ENABLED

    func test_traceparentInjected_whenEnabled() throws {
        TraceparentTestURLProtocol.stub = (200, ["Content-Type": "application/json"], Data("{}".utf8))
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/api/data"))
        performRequest(url: url)
        forceFlush()

        let header = TraceparentTestURLProtocol.lastTraceparentHeader
        XCTAssertNotNil(header, "traceparent header must be present when injection is enabled")
    }

    func test_traceparentFormat_isW3CCompliant() throws {
        TraceparentTestURLProtocol.stub = (200, [:], Data())
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/format-test"))
        performRequest(url: url)
        forceFlush()

        let header = try XCTUnwrap(TraceparentTestURLProtocol.lastTraceparentHeader, "traceparent must be present")
        let validation = validateTraceparentFormat(header)

        XCTAssertTrue(validation.isValid, "traceparent header must be W3C spec-compliant: \(header)")
        XCTAssertEqual(validation.version, "00", "Version must be 00 for current W3C spec")
        XCTAssertNotNil(validation.traceId, "TraceId must be present and valid")
        XCTAssertNotNil(validation.spanId, "SpanId (parentid) must be present and valid")
        XCTAssertNotNil(validation.flags, "Flags must be present and valid")
    }

    func test_traceparentTraceId_isNotAllZeros() throws {
        TraceparentTestURLProtocol.stub = (200, [:], Data())
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/traceid-test"))
        performRequest(url: url)
        forceFlush()

        let header = try XCTUnwrap(TraceparentTestURLProtocol.lastTraceparentHeader)
        let validation = validateTraceparentFormat(header)
        let traceId = try XCTUnwrap(validation.traceId)

        let allZeros = String(repeating: "0", count: 32)
        XCTAssertNotEqual(traceId, allZeros, "TraceId must not be all zeros (invalid trace)")
    }

    func test_traceparentSpanId_isNotAllZeros() throws {
        TraceparentTestURLProtocol.stub = (200, [:], Data())
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/spanid-test"))
        performRequest(url: url)
        forceFlush()

        let header = try XCTUnwrap(TraceparentTestURLProtocol.lastTraceparentHeader)
        let validation = validateTraceparentFormat(header)
        let spanId = try XCTUnwrap(validation.spanId)

        let allZeros = String(repeating: "0", count: 16)
        XCTAssertNotEqual(spanId, allZeros, "SpanId must not be all zeros (invalid span)")
    }

    func test_traceparentFlags_indicateSampledStatus() throws {
        TraceparentTestURLProtocol.stub = (200, [:], Data())
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/sampled-test"))
        performRequest(url: url)
        forceFlush()

        let header = try XCTUnwrap(TraceparentTestURLProtocol.lastTraceparentHeader)
        let validation = validateTraceparentFormat(header)
        let flags = try XCTUnwrap(validation.flags)

        // Flags should be "01" (sampled) or "00" (not sampled)
        XCTAssertTrue(flags == "00" || flags == "01", "Flags must be 00 or 01, got: \(flags)")
    }

    func test_multipleRequests_haveDifferentSpanIds() throws {
        TraceparentTestURLProtocol.stub = (200, [:], Data())
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])

        var spanIds: [String] = []

        for i in 1...3 {
            let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/request-\(i)"))
            performRequest(url: url)
            forceFlush()
            if let header = TraceparentTestURLProtocol.lastTraceparentHeader {
                let validation = validateTraceparentFormat(header)
                if let spanId = validation.spanId {
                    spanIds.append(spanId)
                }
            }
            TraceparentTestURLProtocol.lastTraceparentHeader = nil
        }

        XCTAssertEqual(spanIds.count, 3, "Should capture 3 spanIds")
        let uniqueSpanIds = Set(spanIds)
        XCTAssertEqual(uniqueSpanIds.count, 3, "Each request should have a unique spanId")
    }

    func test_traceparentInjected_forPOSTRequest() throws {
        TraceparentTestURLProtocol.stub = (201, [:], Data())
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/post-endpoint"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "{\"test\":1}".data(using: .utf8)

        let exp = expectation(description: "POST request")
        URLSession.shared.dataTask(with: request) { _, _, _ in exp.fulfill() }.resume()
        wait(for: [exp], timeout: 5)
        forceFlush()

        let header = TraceparentTestURLProtocol.lastTraceparentHeader
        XCTAssertNotNil(header, "traceparent must be injected for POST requests")
    }

    func test_traceparentInjected_whenNoOptionsKey() throws {
        TraceparentTestURLProtocol.stub = (200, [:], Data())
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/no-options"))
        performRequest(url: url)
        forceFlush()

        let header = TraceparentTestURLProtocol.lastTraceparentHeader
        XCTAssertNotNil(header, "traceparent must be injected when no options key (no allowedTracingUrls restriction)")
    }

    func test_traceparentInjected_usingEnabledKey_whenEnableNotPresent() throws {
        TraceparentTestURLProtocol.stub = (200, [:], Data())
        startRUM(traceParentInHeader: ["enabled": true])

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/enabled-key-only"))
        performRequest(url: url)
        forceFlush()

        let header = TraceparentTestURLProtocol.lastTraceparentHeader
        XCTAssertNotNil(header, "traceparent must be injected when using enabled: true (RN bridge key)")
    }

    // MARK: - Unit Tests: shouldAddTraceParent logic (avoids swizzling state issues)

    func test_shouldAddTraceParent_returnsFalse_whenConfigIsNil() throws {
        let options = makeOptions(traceParentInHeader: nil)
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true]) // Initialize SDK
        let r = try XCTUnwrap(rum)

        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/api")))
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertFalse(result, "shouldAddTraceParent must return false when traceParentInHeader is nil")
    }

    func test_shouldAddTraceParent_returnsFalse_whenDisabled_enableFalse() throws {
        let options = makeOptions(traceParentInHeader: [Keys.enable.rawValue: false])
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])
        let r = try XCTUnwrap(rum)

        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/api")))
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertFalse(result, "shouldAddTraceParent must return false when enable: false")
    }

    func test_shouldAddTraceParent_returnsFalse_whenDisabled_enabledFalse_RNKey() throws {
        let options = makeOptions(traceParentInHeader: ["enabled": false])
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])
        let r = try XCTUnwrap(rum)

        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/api")))
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertFalse(result, "shouldAddTraceParent must return false when enabled: false (RN key)")
    }

    func test_shouldAddTraceParent_returnsFalse_forCoralogixDomain() throws {
        let options = makeOptions(traceParentInHeader: [Keys.enable.rawValue: true], coralogixDomain: .US2)
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])
        let r = try XCTUnwrap(rum)

        // URL contains the Coralogix domain
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://ingress.\(CoralogixDomain.US2.rawValue)/v1/logs")))
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertFalse(result, "shouldAddTraceParent must return false for Coralogix domain URLs")
    }

    func test_shouldAddTraceParent_returnsTrue_whenEnabled_noAllowlist() throws {
        let options = makeOptions(traceParentInHeader: [Keys.enable.rawValue: true])
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])
        let r = try XCTUnwrap(rum)

        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/data")))
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertTrue(result, "shouldAddTraceParent must return true when enabled with no allowlist")
    }

    func test_shouldAddTraceParent_returnsTrue_whenUrlInAllowlist() throws {
        let allowedUrl = "https://allowed.example.com/api"
        let options = makeOptions(traceParentInHeader: [
            Keys.enable.rawValue: true,
            "options": ["allowedTracingUrls": [allowedUrl]]
        ])
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])
        let r = try XCTUnwrap(rum)

        let request = URLRequest(url: try XCTUnwrap(URL(string: allowedUrl)))
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertTrue(result, "shouldAddTraceParent must return true when URL is in allowedTracingUrls")
    }

    func test_shouldAddTraceParent_returnsFalse_whenUrlNotInAllowlist() throws {
        let options = makeOptions(traceParentInHeader: [
            Keys.enable.rawValue: true,
            "options": ["allowedTracingUrls": ["https://allowed.example.com"]]
        ])
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])
        let r = try XCTUnwrap(rum)

        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://other.example.com/api")))
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertFalse(result, "shouldAddTraceParent must return false when URL is not in allowedTracingUrls")
    }

    func test_shouldAddTraceParent_returnsTrue_whenUrlMatchesRegexPattern() throws {
        let options = makeOptions(traceParentInHeader: [
            Keys.enable.rawValue: true,
            "options": ["allowedTracingUrls": [".*api\\.example\\.com.*"]]
        ])
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])
        let r = try XCTUnwrap(rum)

        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/v1/data")))
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertTrue(result, "shouldAddTraceParent must return true when URL matches regex in allowedTracingUrls")
    }

    func test_shouldAddTraceParent_enableKeyTakesPrecedence_overEnabledKey() throws {
        // enable: true takes precedence over enabled: false
        let options = makeOptions(traceParentInHeader: [Keys.enable.rawValue: true, "enabled": false])
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])
        let r = try XCTUnwrap(rum)

        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/api")))
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertTrue(result, "enable key must take precedence over enabled key")
    }

    func test_shouldAddTraceParent_returnsFalse_whenRequestUrlIsNil() throws {
        let options = makeOptions(traceParentInHeader: [Keys.enable.rawValue: true])
        startRUM(traceParentInHeader: [Keys.enable.rawValue: true])
        let r = try XCTUnwrap(rum)

        // Create a request with no URL (edge case)
        var request = URLRequest(url: URL(string: "https://placeholder.com")!)
        request.url = nil
        let result = r.shouldAddTraceParent(to: request, options: options)

        XCTAssertFalse(result, "shouldAddTraceParent must return false when request URL is nil")
    }
}
