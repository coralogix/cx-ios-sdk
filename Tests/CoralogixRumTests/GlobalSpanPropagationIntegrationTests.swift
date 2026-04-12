//
//  GlobalSpanPropagationIntegrationTests.swift
//  CoralogixRumTests
//
//  Integration coverage for custom global span + auto-instrumentation:
//  - CX-35954: `registeredGlobalForAutoInstrumentationParent()` + `URLSessionLogger.applyNetworkAutoInstrumentationParentPolicy`
//    / `CoralogixRum.applyAutoInstrumentationParentPolicy` — same trace when global is active or when active OTel
//    context is empty on async work (explicit `setParent(global)`).
//  - CX-35955: `ignoredInstruments` on the tracer passed to `startGlobalSpan` — matching instruments use `setNoParent()`
//    (fresh trace for network / makeSpan userInteraction / error).
//

import XCTest
import CoralogixInternal
@testable import Coralogix

// MARK: - URLProtocol stub (same pattern as NetworkCaptureIntegrationTests)

private final class PropagationTestURLProtocol: URLProtocol {
    static var stub: (status: Int, headers: [String: String], body: Data)?
    static let scheme = "proptest"

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == scheme
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "PropagationTest", code: -1, userInfo: nil))
            return
        }
        let url = request.url ?? URL(string: "proptest://localhost/")!
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class GlobalSpanPropagationIntegrationTests: XCTestCase {

    static let baseURL = "proptest://cx35954"
    var rum: CoralogixRum?
    var capturedSpans: [SpanData] = []
    let captureLock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        capturedSpans = []
        URLProtocol.registerClass(PropagationTestURLProtocol.self)
        CoralogixExporter.testExportCallback = { [weak self] spans in
            self?.captureLock.lock()
            self?.capturedSpans.append(contentsOf: spans)
            self?.captureLock.unlock()
        }
    }

    override func tearDownWithError() throws {
        CoralogixCustomGlobalSpanRegistry.shared.teardownIfNeeded()
        rum = nil
        CoralogixRum.isInitialized = false
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        CoralogixExporter.testExportCallback = nil
        capturedSpans = []
        URLProtocol.unregisterClass(PropagationTestURLProtocol.self)
        try super.tearDownWithError()
    }

    func makeOptions() -> CoralogixExporterOptions {
        CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: nil,
            environment: "test",
            application: "CX35954Propagation",
            version: "1.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            instrumentations: [.network: true],
            traceParentInHeader: [Keys.enable.rawValue: true],
            networkExtraConfig: [NetworkCaptureRule(url: Self.baseURL)],
            debug: true
        )
    }

    func startRUM() {
        rum = CoralogixRum(options: makeOptions())
        XCTAssertTrue(CoralogixRum.isInitialized)
    }

    func forceFlush() {
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.6)
    }

    func waitForNetworkSpan(urlContains: String, timeout: TimeInterval = 8) -> SpanData? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            forceFlush()
            captureLock.lock()
            // URLSession instrumentation may emit more than one client span per request (factory + resume paths).
            // Assert against the last matching export for this URL so we validate the span built with final parent policy.
            let match = capturedSpans.last { span in
                let type = span.attributes[Keys.eventType.rawValue]?.description ?? ""
                guard type.contains(CoralogixEventType.networkRequest.rawValue) else { return false }
                guard let url = span.attributes[SemanticAttributes.httpUrl.rawValue]?.description else { return false }
                return url.contains(urlContains)
            }
            captureLock.unlock()
            if let match {
                return match
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return nil
    }

    // MARK: - CX-35954 (inherit global trace)

    func testGlobalSpan_makeSpan_sameThread_userInteraction_inheritsGlobal() throws {
        startRUM()
        let r = try XCTUnwrap(rum)
        guard let tracer = r.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "ui.main") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        var span = r.makeSpan(event: .userInteraction, source: .console, severity: .info)
        defer { span.end() }
        guard let readable = span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let data = readable.toSpanData()
        XCTAssertEqual(data.traceId, globalData.traceId, "Same-thread UI span should parent via active OTel context (CX-35954)")
        XCTAssertEqual(data.parentSpanId, globalData.spanId)
    }

    func testGlobalSpan_networkRequest_sameThread_sharesTraceAndParent() throws {
        PropagationTestURLProtocol.stub = (200, ["Content-Type": "application/json"], Data("{}".utf8))
        startRUM()
        let sdk = try XCTUnwrap(rum)
        guard let tracer = sdk.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "flow.root") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/sync"))
        let exp = expectation(description: "request")
        URLSession.shared.dataTask(with: url) { _, _, _ in exp.fulfill() }.resume()
        wait(for: [exp], timeout: 5)

        let net = try XCTUnwrap(waitForNetworkSpan(urlContains: "cx35954"), "Exported network span must appear")
        XCTAssertEqual(net.traceId, globalData.traceId, "Network span must use global trace id")
        XCTAssertEqual(net.parentSpanId, globalData.spanId, "Network span parent must be global span id")
    }

    func testGlobalSpan_networkRequest_fromBackgroundQueue_sharesTraceAndParent() throws {
        PropagationTestURLProtocol.stub = (200, [:], Data())
        startRUM()
        let sdk = try XCTUnwrap(rum)
        guard let tracer = sdk.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "flow.async") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        let exp = expectation(description: "bg request")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = URL(string: "\(Self.baseURL)/async") else {
                XCTFail("Invalid URL")
                exp.fulfill()
                return
            }
            URLSession.shared.dataTask(with: url) { _, _, _ in exp.fulfill() }.resume()
        }
        wait(for: [exp], timeout: 8)

        let net = try XCTUnwrap(waitForNetworkSpan(urlContains: "async"), "Network span must inherit global trace when URLSession runs off main (CX-35954)")
        XCTAssertEqual(net.traceId, globalData.traceId)
        XCTAssertEqual(net.parentSpanId, globalData.spanId)
    }

    func testGlobalSpan_makeSpanOnBackgroundQueue_userInteraction_parentsUnderGlobal() throws {
        startRUM()
        let r = try XCTUnwrap(rum)
        guard let tracer = r.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "ui.flow") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        let exp = expectation(description: "bg makeSpan")
        DispatchQueue.global(qos: .userInitiated).async {
            var span = r.makeSpan(event: .userInteraction, source: .console, severity: .info)
            defer { span.end() }
            guard let readable = span as? any ReadableSpan else {
                XCTFail("Expected ReadableSpan")
                exp.fulfill()
                return
            }
            let data = readable.toSpanData()
            XCTAssertEqual(data.traceId, globalData.traceId, "User interaction span must use global trace id")
            XCTAssertEqual(data.parentSpanId, globalData.spanId, "User interaction span must parent under global when active context is nil on worker queue")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
    }

    // MARK: - CX-35955 (ignoredInstruments → setNoParent for matching auto spans)

    /// Only `.userInteractions` is ignored — URLSession network spans must still join the global trace.
    func testIgnoredInstruments_userInteractionsOnly_networkStillInheritsGlobal() throws {
        PropagationTestURLProtocol.stub = (200, [:], Data())
        startRUM()
        let r = try XCTUnwrap(rum)
        guard let tracer = r.getCustomTracer(ignoredInstruments: [.userInteractions]) else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "partial-net") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/ui-ignored-net"))
        let exp = expectation(description: "request")
        URLSession.shared.dataTask(with: url) { _, _, _ in exp.fulfill() }.resume()
        wait(for: [exp], timeout: 5)

        let net = try XCTUnwrap(waitForNetworkSpan(urlContains: "ui-ignored-net"))
        XCTAssertEqual(net.traceId, globalData.traceId, "Network must still inherit global when only userInteractions is ignored (CX-35955)")
        XCTAssertEqual(net.parentSpanId, globalData.spanId)
    }

    /// Only `.errors` is ignored — network must still inherit global.
    func testIgnoredInstruments_errorsOnly_networkStillInheritsGlobal() throws {
        PropagationTestURLProtocol.stub = (200, [:], Data())
        startRUM()
        let r = try XCTUnwrap(rum)
        guard let tracer = r.getCustomTracer(ignoredInstruments: [.errors]) else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "partial-err") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/err-ignored-net"))
        let exp = expectation(description: "request")
        URLSession.shared.dataTask(with: url) { _, _, _ in exp.fulfill() }.resume()
        wait(for: [exp], timeout: 5)

        let net = try XCTUnwrap(waitForNetworkSpan(urlContains: "err-ignored-net"))
        XCTAssertEqual(net.traceId, globalData.traceId)
        XCTAssertEqual(net.parentSpanId, globalData.spanId)
    }

    func testIgnoredInstruments_networkRequests_networkSpanUsesSeparateTrace() throws {
        PropagationTestURLProtocol.stub = (200, [:], Data())
        startRUM()
        let r = try XCTUnwrap(rum)
        guard let tracer = r.getCustomTracer(ignoredInstruments: [.networkRequests]) else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "ignored.net") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        let url = try XCTUnwrap(URL(string: "\(Self.baseURL)/ignored-net"))
        let exp = expectation(description: "request")
        URLSession.shared.dataTask(with: url) { _, _, _ in exp.fulfill() }.resume()
        wait(for: [exp], timeout: 5)

        let net = try XCTUnwrap(waitForNetworkSpan(urlContains: "ignored-net"))
        XCTAssertNotEqual(net.traceId, globalData.traceId, "Ignored network must not share global trace id (CX-35955)")
        XCTAssertNil(net.parentSpanId, "Ignored network span must be a root span")
    }

    func testIgnoredInstruments_userInteractions_makeSpanUsesSeparateTrace() throws {
        startRUM()
        let r = try XCTUnwrap(rum)
        guard let tracer = r.getCustomTracer(ignoredInstruments: [.userInteractions]) else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "ignored.ui") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        var span = r.makeSpan(event: .userInteraction, source: .console, severity: .info)
        defer { span.end() }
        guard let readable = span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let data = readable.toSpanData()
        XCTAssertNotEqual(data.traceId, globalData.traceId)
        XCTAssertNil(data.parentSpanId)
    }

    func testIgnoredInstruments_errors_makeSpanUsesSeparateTrace() throws {
        startRUM()
        let r = try XCTUnwrap(rum)
        guard let tracer = r.getCustomTracer(ignoredInstruments: [.errors]) else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "ignored.err") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        var span = r.makeSpan(event: .error, source: .console, severity: .error)
        defer { span.end() }
        guard let readable = span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let data = readable.toSpanData()
        XCTAssertNotEqual(data.traceId, globalData.traceId)
        XCTAssertNil(data.parentSpanId)
    }

    /// When only network is ignored, user-interaction auto spans must still inherit the global trace.
    func testIgnoredInstruments_networkOnly_userInteractionStillInheritsGlobal() throws {
        startRUM()
        let r = try XCTUnwrap(rum)
        guard let tracer = r.getCustomTracer(ignoredInstruments: [.networkRequests]) else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "partial") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        var span = r.makeSpan(event: .userInteraction, source: .console, severity: .info)
        defer { span.end() }
        guard let readable = span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let data = readable.toSpanData()
        XCTAssertEqual(data.traceId, globalData.traceId)
        XCTAssertEqual(data.parentSpanId, globalData.spanId)
    }
}
