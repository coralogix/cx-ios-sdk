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

    /// Splits a W3C `traceparent` (version-traceid-spanid-flags) into its fields.
    private func parseTraceparent(_ header: String) throws -> (traceId: String, spanId: String, flags: String) {
        let parts = header.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else {
            throw XCTSkip("traceparent is not W3C-shaped: \(header)")
        }
        return (parts[1], parts[2], parts[3])
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
        let wire = try parseTraceparent(header)
        XCTAssertEqual(wire.traceId.count, 32, "wire trace id must be 32 hex chars, got: \(wire.traceId)", file: file, line: line)
        XCTAssertEqual(wire.spanId.count, 16, "wire span id must be 16 hex chars, got: \(wire.spanId)", file: file, line: line)

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
}
