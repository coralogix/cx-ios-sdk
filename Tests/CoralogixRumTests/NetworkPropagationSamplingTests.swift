//
//  NetworkPropagationSamplingTests.swift
//
//  End-to-end cover for the propagate-only network state: a sampled-out session must still put
//  `traceparent` on the wire while reporting no `network-request` event, and must report the event
//  once `.network` is listed in `excludeFromSampling`.
//
//  The decision itself is unit-tested in `InstrumentationGatingTests`. These tests drive a real
//  `URLSession` request through the swizzles instead, because the install decision, the header
//  injection and the export filter are three separate mechanisms and only a request exercises all
//  three together.
//
//  Export is observed through `tracesExporter`, NOT `CoralogixExporter.testExportCallback`: the test
//  callback fires on the raw batch at the top of `export()`, above the sampling and network-reporting
//  filters, so it cannot tell a dropped span from a kept one.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

private final class PropagationTestURLProtocol: URLProtocol {
    static let scheme = "cx52134propagation"

    /// `startLoading()` runs on the URL loading system's thread while the assertions read from the
    /// test thread, so the storage is lock-guarded and only reachable through these accessors.
    private static let lock = NSLock()
    private static var _lastTraceparent: String?

    static var lastTraceparent: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastTraceparent
    }

    private static func record(traceparent: String?) {
        lock.lock()
        defer { lock.unlock() }
        _lastTraceparent = traceparent
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == scheme
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Records what this request actually carried, nil included, so a header from an earlier
        // request in the same test can never be mistaken for this one's.
        var captured: String?
        if let fields = request.allHTTPHeaderFields {
            for (key, value) in fields where key.lowercased() == "traceparent" {
                captured = value
            }
        }
        Self.record(traceparent: captured)
        let url = request.url ?? URL(string: "\(Self.scheme)://localhost/")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() { record(traceparent: nil) }
}

final class NetworkPropagationSamplingTests: XCTestCase {

    private var rum: CoralogixRum?
    private var capture: EventTypeCapture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        CoralogixRum.isInitialized = false
        capture = EventTypeCapture()
        PropagationTestURLProtocol.reset()
        URLProtocol.registerClass(PropagationTestURLProtocol.self)
    }

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        CoralogixRum.isInitialized = false
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        PropagationTestURLProtocol.reset()
        URLProtocol.unregisterClass(PropagationTestURLProtocol.self)
        try super.tearDownWithError()
    }

    private func startRUM(sampleRate: Int = 0,
                          exclude: Set<ExcludableInstrumentation>,
                          instrumentations: [CoralogixExporterOptions.InstrumentationType: Bool]? = nil,
                          propagation: Bool = true) throws {
        let options = makeSamplingOptions(sampleRate: sampleRate,
                                         exclude: exclude,
                                         instrumentations: instrumentations,
                                         traceParentInHeader: propagation ? traceParentEnabled : nil,
                                         tracesExporter: capture.tracesExporterCallback())
        let rum = CoralogixRum(options: options)
        self.rum = rum
        XCTAssertTrue(CoralogixRum.isInitialized,
                      "Init must proceed so the swizzles exist to inject the header.")
        try XCTUnwrap(rum.coralogixExporter).spanUploader = SamplingMockSpanUploader()
    }

    private func performRequest(path: String) {
        let url = URL(string: "\(PropagationTestURLProtocol.scheme)://cx52134/\(path)")!
        let exp = expectation(description: "request \(path)")
        URLSession.shared.dataTask(with: url) { _, _, _ in exp.fulfill() }.resume()
        wait(for: [exp], timeout: 5)
    }

    private func forceFlush() {
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Case 5: sampled out, propagate only
    //
    // Note this row is dropped by `passesSessionSampling`, not by `reportsNetworkEvents` — a
    // sampled-out session with `.network` unexcluded fails the sampling filter first. Verified by
    // sabotaging the propagate-only gate, which left this test green. The gate's own end-to-end
    // cover is `testSampledIn_networkReportingOff_...` below.

    func testSampledOut_noExclude_injectsTraceparentButReportsNoNetworkEvent() throws {
        try startRUM(exclude: [])

        performRequest(path: "propagate-only")
        forceFlush()

        let header = try XCTUnwrap(PropagationTestURLProtocol.lastTraceparent,
                                   "A sampled-out session must still inject traceparent — that is the whole point of keeping network instrumentation installed.")
        XCTAssertEqual(header.split(separator: "-").count, 4, "Header must stay W3C-shaped: \(header)")

        XCTAssertFalse(capture.eventTypes.contains(CoralogixEventType.networkRequest.rawValue),
                       "Propagate-only: the request must not surface as a network-request event. Saw \(capture.eventTypes).")
    }

    // MARK: - Sampled out, propagation OFF: nothing to inject, so nothing installs

    func testSampledOut_noExcludeNoPropagation_installsNothingAndReportsNothing() throws {
        let options = makeSamplingOptions(sampleRate: 0,
                                         exclude: [],
                                         tracesExporter: capture.tracesExporterCallback())
        try startRUM(exclude: [], propagation: false)

        performRequest(path: "no-propagation")
        forceFlush()

        XCTAssertFalse(CoralogixRum.shouldInstall(.network, options: options, sampledIn: false),
                       "Nothing to propagate and nothing to report, so network must not be installed.")
        XCTAssertFalse(capture.eventTypes.contains(CoralogixEventType.networkRequest.rawValue),
                       "No event may be reported. Saw \(capture.eventTypes).")

        // Deliberately no assertion on the wire here. Swizzles are process-global and never
        // uninstalled, and `shutdown()` does not clear `NetworkInstrumentation.currentNetworkOptions`
        // — the statics are intentional, so that closures surviving a reinitialization can read the
        // latest config. A prior test in this process installed them with propagation on, and those
        // leftovers keep injecting from the stale options. The same is true of a host app that
        // reinitializes the SDK: "network is off" means the SDK stops installing and updating the
        // instrumentation, not that previously-installed swizzles disappear. In a fresh process
        // nothing is installed and nothing is injected, which is what the decision above asserts.
    }

    // MARK: - Sampled out, network excluded, propagation OFF: reports without a header
    //
    // The row that shows the two concerns really are independent: excluding network from sampling
    // restores the event, while the header still obeys traceParentInHeader alone.

    func testSampledOut_excludeNetworkNoPropagation_reportsEventWithoutInjecting() throws {
        try startRUM(exclude: [.network], propagation: false)

        performRequest(path: "excluded-no-propagation")
        forceFlush()

        XCTAssertNil(PropagationTestURLProtocol.lastTraceparent,
                     "traceParentInHeader is off, so no header goes out even though the event is reported.")
        XCTAssertTrue(capture.eventTypes.contains(CoralogixEventType.networkRequest.rawValue),
                      "Excluding network from sampling reports the event regardless of propagation. Saw \(capture.eventTypes).")
    }

    // MARK: - Sampled IN, network switched off: the outer gate silences both
    //
    // Browser parity: a disabled instrumentation is never registered with the OTel provider, so
    // there is nothing left to inject regardless of traceParentInHeader. Contrast with the
    // sampled-out rows above, where propagation survives — sampling silences reporting without
    // silencing propagation, the caller's own switch silences both.

    func testSampledIn_networkOff_injectsNothingAndReportsNothing() throws {
        try startRUM(sampleRate: 100, exclude: [], instrumentations: [.network: false])

        performRequest(path: "network-off")
        forceFlush()

        XCTAssertFalse(capture.eventTypes.contains(CoralogixEventType.networkRequest.rawValue),
                       "No network event may be reported. Saw \(capture.eventTypes).")
        XCTAssertFalse(capture.eventTypes.isEmpty,
                       "Sanity: the capture must be receiving something, otherwise the assertion above is vacuous.")

        // No wire assertion, for the reason given on the no-propagation row above: swizzles from an
        // earlier test in this process are still installed and still injecting from stale statics.
        // The install decision is asserted directly in InstrumentationGatingTests instead.
    }

    // MARK: - Case 7: excluded from sampling, so it reports

    func testSampledOut_excludeNetwork_injectsTraceparentAndReportsNetworkEvent() throws {
        try startRUM(exclude: [.network])

        performRequest(path: "excluded")
        forceFlush()

        XCTAssertNotNil(PropagationTestURLProtocol.lastTraceparent,
                        "Excluding network from sampling must not stop header injection.")
        XCTAssertTrue(capture.eventTypes.contains(CoralogixEventType.networkRequest.rawValue),
                      "With .network excluded from sampling the event must reach the exporter. Saw \(capture.eventTypes).")
    }
}
