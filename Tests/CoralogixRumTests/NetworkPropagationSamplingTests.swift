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
                          instrumentations: [CoralogixExporterOptions.InstrumentationType: Bool]? = nil) throws {
        let options = makeSamplingOptions(sampleRate: sampleRate,
                                         exclude: exclude,
                                         instrumentations: instrumentations,
                                         traceParentInHeader: traceParentEnabled,
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

    // MARK: - Case 4a: sampled IN, reporting off, propagation on
    //
    // The only row where `reportsNetworkEvents` is load-bearing. The session is sampled in, so the
    // span is stamped sampled-in and sails through `passesSessionSampling`; only the propagate-only
    // gate can stop it. Confirmed falsifiable: forcing that gate to return true turns this red.

    func testSampledIn_networkReportingOff_injectsTraceparentButReportsNoNetworkEvent() throws {
        try startRUM(sampleRate: 100, exclude: [], instrumentations: [.network: false])

        performRequest(path: "reporting-off")
        forceFlush()

        XCTAssertNotNil(PropagationTestURLProtocol.lastTraceparent,
                        "Disabling network reporting must not stop header injection while traceParentInHeader is on.")
        XCTAssertFalse(capture.eventTypes.contains(CoralogixEventType.networkRequest.rawValue),
                       "instrumentations[.network] = false must suppress the event even on a sampled-in session. Saw \(capture.eventTypes).")
        XCTAssertFalse(capture.eventTypes.isEmpty,
                       "Sanity: the capture must be receiving something, otherwise the assertion above is vacuous.")
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
