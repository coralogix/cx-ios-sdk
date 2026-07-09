//
//  TraceparentExportedSpanCorrelationTests.swift
//  CoralogixRumTests
//
//  Regression tests: the `traceparent` header injected into an outgoing request MUST carry the
//  same trace id AND span id as the network span the SDK exports for that request. If they differ,
//  backend spans (children of the wire traceparent) and the RUM span land on two different traces
//  and can never be stitched — defeating the purpose of `traceParentInHeader`.
//
//  The defect this guards against: a task created via a URLSession factory method was instrumented
//  twice — the factory swizzle made span A and put A's traceparent on the wire; the resume swizzle
//  then made span B that overwrote A in `runningSpans`, so B was exported while the wire kept A (and
//  A leaked, never ended). `TraceparentHeaderInjectionTests` only validate the header is W3C-shaped;
//  they never compare it to the exported span — which is why that regression went unnoticed.
//
//  Coverage below spans the task-creation paths that reach the resume swizzle. The completion-handler
//  and no-completion request paths go red on the unfixed code (wire=A, exported=B); the bare-URL path
//  is a regression guard for the same invariant (there the fix also stops span A leaking); the
//  async/await `data(for:)` path confirms the invariant holds for Swift concurrency too.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

// MARK: - URLProtocol stub for capturing the wire traceparent

private final class CorrelationTestURLProtocol: URLProtocol {
    static var stub: (status: Int, headers: [String: String], body: Data)?
    static var lastTraceparentHeader: String?
    static let scheme = "traceparentcorrelationtest"

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
        Self.lastTraceparentHeader = Self.header(from: request, named: "traceparent")

        guard let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "CorrelationTest", code: -1, userInfo: nil))
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
        lastTraceparentHeader = nil
    }
}

// MARK: - Tests

final class TraceparentExportedSpanCorrelationTests: XCTestCase {

    static let baseURL = "traceparentcorrelationtest://correlation"
    var rum: CoralogixRum?
    var capturedSpans: [SpanData] = []
    let captureLock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        capturedSpans = []
        CorrelationTestURLProtocol.reset()
        URLProtocol.registerClass(CorrelationTestURLProtocol.self)
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
        CorrelationTestURLProtocol.reset()
        URLProtocol.unregisterClass(CorrelationTestURLProtocol.self)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    func startRUM() {
        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: nil,
            environment: "test",
            application: "TraceparentCorrelationTests",
            version: "1.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            instrumentations: [.network: true],
            traceParentInHeader: [Keys.enable.rawValue: true],
            debug: true
        )
        rum = CoralogixRum(options: options)
        XCTAssertTrue(CoralogixRum.isInitialized)
    }

    func forceFlush() {
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func attributeString(_ value: AttributeValue?) -> String? {
        if case let .string(s)? = value { return s }
        return nil
    }

    /// Splits a W3C `traceparent` (version-traceid-spanid-flags) into its fields, validating full W3C
    /// compliance first (each field lowercase hex of the spec length: version 2, traceid 32, spanid 16,
    /// flags 2). A malformed header — wrong field count, non-hex, wrong length, or uppercase — is a real
    /// failure (not a skip), so the regression test can't silently pass if the SDK ever injects a
    /// non-W3C `traceparent`.
    private func parseTraceparent(_ header: String,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) throws -> (traceId: String, spanId: String, flags: String) {
        let parts = header.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        let fields: (traceId: String, spanId: String, flags: String)? =
            Self.isW3CTraceparent(header) ? (parts[1], parts[2], parts[3]) : nil
        return try XCTUnwrap(fields,
                             "traceparent is not W3C-compliant (version-traceid-spanid-flags, lowercase hex, lengths 2/32/16/2): \(header)",
                             file: file, line: line)
    }

    /// True when `header` is a fully W3C-compliant `traceparent`: exactly four `-`-separated fields
    /// (version, trace id, span id, flags), each lowercase hex of length 2 / 32 / 16 / 2.
    private static func isW3CTraceparent(_ header: String) -> Bool {
        let parts = header.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 4
            && isLowercaseHex(parts[0], length: 2)    // version
            && isLowercaseHex(parts[1], length: 32)   // trace id
            && isLowercaseHex(parts[2], length: 16)   // span id (parent id)
            && isLowercaseHex(parts[3], length: 2)    // trace flags
    }

    /// True when `s` is exactly `length` lowercase-hex characters (`[0-9a-f]`).
    private static func isLowercaseHex(_ s: String, length: Int) -> Bool {
        s.count == length && s.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase }
    }

    /// Force-flushes and polls the captured spans until a network span for `url` appears (or timeout),
    /// then returns every exported network span for that URL. Polling makes the delegate/async paths
    /// robust against export timing without relying on a specific completion callback ordering.
    private func waitForNetworkSpans(url: URL, timeout: TimeInterval = 8) -> [SpanData] {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            forceFlush()
            captureLock.lock()
            let spans = capturedSpans.filter {
                attributeString($0.attributes[SemanticAttributes.httpUrl.rawValue]) == url.absoluteString
            }
            captureLock.unlock()
            if !spans.isEmpty { return spans }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return []
    }

    /// THE invariant: exactly one network span is exported for the request, and its trace id AND span id
    /// equal the trace id / parent-span id on the wire `traceparent`. Span-id equality (not just trace id)
    /// is what pins the exported span to the exact span whose context went on the wire.
    private func assertExportedSpanMatchesWire(url: URL,
                                               exportedSpans: [SpanData],
                                               file: StaticString = #filePath,
                                               line: UInt = #line) throws {
        let header = try XCTUnwrap(CorrelationTestURLProtocol.lastTraceparentHeader,
                                   "traceparent must be injected on the wire when enabled",
                                   file: file, line: line)
        // parseTraceparent already validates W3C shape/lengths (version 2, traceid 32, spanid 16, flags 2).
        let wire = try parseTraceparent(header, file: file, line: line)

        XCTAssertEqual(exportedSpans.count, 1,
                       "exactly one network span must be exported per request — more than one (or the wrong one) means the task was instrumented twice",
                       file: file, line: line)

        for span in exportedSpans {
            XCTAssertEqual(span.traceId.hexString, wire.traceId,
                           "exported network span is on a different trace than the wire traceparent (wire=\(wire.traceId) exported=\(span.traceId.hexString)) — backend spans parent to the wire trace, so the RUM span can never be stitched to them",
                           file: file, line: line)
            XCTAssertEqual(span.spanId.hexString, wire.spanId,
                           "exported network span id differs from the wire traceparent parent-span id (wire=\(wire.spanId) exported=\(span.spanId.hexString)) — the exported span is not the one whose context was put on the wire",
                           file: file, line: line)
        }
    }

    // MARK: - Completion-handler request task (red→green)

    /// `dataTask(with: request, completionHandler:)` — the path in the original bug report.
    func test_completionHandlerRequestTask_exportedSpanMatchesWire() throws {
        CorrelationTestURLProtocol.stub = (200, ["Content-Type": "application/json"], Data("{}".utf8))
        startRUM()

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/completion-handler"))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let exp = expectation(description: "request completes")
        URLSession.shared.dataTask(with: request) { _, _, _ in exp.fulfill() }.resume()
        wait(for: [exp], timeout: 5)

        let spans = waitForNetworkSpans(url: url)
        try assertExportedSpanMatchesWire(url: url, exportedSpans: spans)
    }

    // MARK: - Request task without completion handler (red→green)

    /// `dataTask(with: request)` + `resume()` with no completion handler — the delegate/streaming
    /// pattern (e.g. long-poll clients). The factory injects span A on the wire; the resume swizzle
    /// used to export span B on a different trace. No completion handler here, so the SDK's own
    /// FakeDelegate drives completion; the span is observed by polling the export callback.
    func test_noCompletionHandlerRequestTask_exportedSpanMatchesWire() throws {
        CorrelationTestURLProtocol.stub = (200, ["Content-Type": "application/json"], Data("{}".utf8))
        startRUM()

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/no-completion"))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request).resume()

        let spans = waitForNetworkSpans(url: url)
        try assertExportedSpanMatchesWire(url: url, exportedSpans: spans)
    }

    // MARK: - Bare-URL task (regression guard)

    /// `dataTask(with: url)` + `resume()`. The factory creates span A but injects nothing on the wire
    /// (there is no request to inject into then); injection is completed at resume with the EXISTING
    /// span's context. This guards that the fix keeps injecting for bare-URL tasks and that the wire
    /// header matches the single exported span (previously span A leaked here, unended).
    func test_bareURLTask_exportedSpanMatchesWire() throws {
        CorrelationTestURLProtocol.stub = (200, ["Content-Type": "application/json"], Data("{}".utf8))
        startRUM()

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/bare-url"))
        URLSession.shared.dataTask(with: url).resume()

        let spans = waitForNetworkSpans(url: url)
        try assertExportedSpanMatchesWire(url: url, exportedSpans: spans)
    }

    // MARK: - async/await task

    /// `data(for:)` — the async/await path. Routed through a dedicated session with the stub pinned in
    /// `configuration.protocolClasses`; the globally registered stub is removed first so the async path
    /// resolves solely via the session's protocol list (registering the same class both globally and on
    /// the session does not route reliably for async `data(for:)`). Confirms the wire `traceparent` and
    /// the exported span stay correlated on the async path too.
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func test_asyncAwaitTask_exportedSpanMatchesWire() async throws {
        URLProtocol.unregisterClass(CorrelationTestURLProtocol.self)
        CorrelationTestURLProtocol.stub = (200, ["Content-Type": "application/json"], Data("{}".utf8))
        startRUM()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CorrelationTestURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/async-await"))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        _ = try await session.data(for: request)

        let spans = waitForNetworkSpans(url: url)
        try assertExportedSpanMatchesWire(url: url, exportedSpans: spans)
    }

    // MARK: - traceparent validation (unit)

    /// The correlation assertions lean on `parseTraceparent` rejecting anything that isn't a W3C
    /// `traceparent`; if it accepted malformed headers, a broken injection could slip through green.
    /// Pins the validator: a valid header parses into its fields, and non-hex / uppercase / wrong-length
    /// / short headers are rejected.
    func test_parseTraceparent_acceptsW3C_rejectsMalformed() throws {
        let valid = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
        let fields = try parseTraceparent(valid)
        XCTAssertEqual(fields.traceId, "0af7651916cd43dd8448eb211c80319c")
        XCTAssertEqual(fields.spanId, "b7ad6b7169203331")
        XCTAssertEqual(fields.flags, "01")

        XCTAssertFalse(Self.isW3CTraceparent("zz-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"),
                       "non-hex version (zz) must be rejected")
        XCTAssertFalse(Self.isW3CTraceparent("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-gg"),
                       "non-hex flags (gg) must be rejected")
        XCTAssertFalse(Self.isW3CTraceparent("00-0AF7651916CD43DD8448EB211C80319C-b7ad6b7169203331-01"),
                       "uppercase trace id must be rejected")
        XCTAssertFalse(Self.isW3CTraceparent("00-0af7651916cd43dd8448eb211c80319c-b7ad6b71692033-01"),
                       "wrong-length span id must be rejected")
        XCTAssertFalse(Self.isW3CTraceparent("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331"),
                       "missing flags field must be rejected")
    }
}
