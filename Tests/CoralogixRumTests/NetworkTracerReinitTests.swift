//
//  NetworkTracerReinitTests.swift
//  CoralogixRumTests
//
//  Network and hybrid spans are built from the SDK's own tracer provider, never from whatever is
//  registered globally, and a second init takes over the one URLSession instrumentation the
//  process has: its native, delegate and hybrid traffic reaches the second instance's exporter.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

// MARK: - Stubs

private final class ReinitURLProtocol: URLProtocol {
    static let host = "tracer-reinit.test"
    static let body = Data(#"{"ok":true}"#.utf8)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Stands in for React Native's session delegate: the SDK instruments a class by this name.
/// The class exists for the whole test process, so every init in it instruments this class; that is
/// harmless, as only sessions using this delegate reach those swizzles.
@objc(RCTHTTPRequestHandler)
private final class FakeRCTHTTPRequestHandler: NSObject, URLSessionDataDelegate {
    var completed: XCTestExpectation?

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {}

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completed?.fulfill()
    }
}

private final class CapturingUploader: SpanUploading {
    private let lock = NSLock()
    private var _events: [[String: Any]] = []

    var events: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
        lock.lock(); defer { lock.unlock() }
        _events.append(contentsOf: spans)
        return .delivered
    }
}

/// Records every span that ends on the provider it is installed in.
private final class RecordingSpanProcessor: SpanProcessor {
    private let lock = NSLock()
    private var _names: [String] = []
    let isStartRequired = false
    let isEndRequired = true

    var endedSpanNames: [String] {
        lock.lock(); defer { lock.unlock() }
        return _names
    }

    func onStart(parentContext: SpanContext?, span: any ReadableSpan) {}
    func onEnd(span: any ReadableSpan) {
        lock.lock(); defer { lock.unlock() }
        _names.append(span.name)
    }
    func shutdown(explicitTimeout: TimeInterval?) {}
    func forceFlush(timeout: TimeInterval?) {}
}

// MARK: - Tests

final class NetworkTracerReinitTests: XCTestCase {

    private var instances: [CoralogixRum] = []
    private var sessions: [URLSession] = []
    /// Restored in tearDown, so a provider a test registers does not outlive it.
    private var globalProviderBefore: TracerProvider?

    override func setUpWithError() throws {
        try super.setUpWithError()
        globalProviderBefore = OpenTelemetry.instance.tracerProvider
    }

    override func tearDownWithError() throws {
        sessions.forEach { $0.invalidateAndCancel() }
        sessions.removeAll()
        instances.forEach { $0.shutdown() }
        instances.removeAll()
        if let globalProviderBefore {
            OpenTelemetry.registerTracerProvider(tracerProvider: globalProviderBefore)
        }
        CoralogixRum.isInitialized = false
        CoralogixRum.mobileSDK = MobileSDK()
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        try super.tearDownWithError()
    }

    // MARK: Explicit tracer

    func test_providerRegisteredGloballyAfterInit_receivesNoNetworkOrHybridSpans() throws {
        let (rum, uploader) = try start(application: "TracerOwnerApp")
        let foreign = RecordingSpanProcessor()
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder().add(spanProcessor: foreign).build())

        let nativeURL = try url("/v1/native-after-foreign")
        try completeRequest(nativeURL, in: makeSession())
        let hybridURL = try url("/v1/hybrid-after-foreign")
        rum.setNetworkRequestContext(dictionary: hybridReport(for: hybridURL))

        XCTAssertNotNil(event(for: nativeURL, in: uploader, flushing: rum),
                        "The network span must reach the SDK's own exporter")
        XCTAssertNotNil(event(for: hybridURL, in: uploader, flushing: rum),
                        "The hybrid span must reach the SDK's own exporter")
        XCTAssertEqual(foreign.endedSpanNames, [],
                       "A provider another library registers globally must not receive SDK spans")
    }

    // MARK: Re-init

    func test_reinit_nativeAndDelegateSpansReachSecondInstance() throws {
        let (first, firstUploader) = try start(application: "FirstApp")
        let (second, secondUploader) = try start(application: "SecondApp")

        let nativeURL = try url("/v1/native-after-reinit")
        try completeRequest(nativeURL, in: makeSession())

        let delegateURL = try url("/v1/rn-delegate-after-reinit")
        let handler = FakeRCTHTTPRequestHandler()
        let done = expectation(description: "delegate completed")
        handler.completed = done
        let delegateSession = makeSession(delegate: handler)
        delegateSession.dataTask(with: URLRequest(url: delegateURL)).resume()
        wait(for: [done], timeout: 5)

        XCTAssertNotNil(event(for: nativeURL, in: secondUploader, flushing: second),
                        "A completion-handler request after re-init must reach the second instance")
        XCTAssertNotNil(event(for: delegateURL, in: secondUploader, flushing: second),
                        "A React Native delegate request after re-init must reach the second instance")
        first.flush()
        XCTAssertNil(event(for: nativeURL, in: firstUploader, flushing: first, timeout: 0.5))
        XCTAssertNil(event(for: delegateURL, in: firstUploader, flushing: first, timeout: 0.5))
    }

    func test_reinit_hybridReportCarriesNativeTraceparent() throws {
        _ = try start(application: "FirstApp")
        let (second, secondUploader) = try start(application: "SecondApp")

        // The bridge reports a request the native layer carried and injected a traceparent into.
        let hybridURL = try url("/v1/hybrid-native-traceparent")
        try completeRequest(hybridURL, in: makeSession())
        second.setNetworkRequestContext(dictionary: hybridReport(for: hybridURL, method: "POST"))

        let hybridEvent = try XCTUnwrap(event(for: hybridURL, in: secondUploader, flushing: second, method: "POST"),
                                        "The hybrid span must reach the second instance")
        let network = try XCTUnwrap(Self.networkContext(hybridEvent))
        let headers = try XCTUnwrap(Self.requestHeaders(network),
                                    "The hybrid event must carry the native request headers")
        let traceparent = try XCTUnwrap(headers["traceparent"],
                                        "The native traceparent must survive re-init; got \(headers)")
        XCTAssertTrue(traceparent.hasPrefix("00-"), "Unexpected traceparent \(traceparent)")
    }

    // MARK: - Helpers

    private func start(application: String) throws -> (CoralogixRum, CapturingUploader) {
        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: nil,
            environment: "reinit-test",
            application: application,
            version: "1.0.0",
            publicKey: "reinit-key",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            instrumentations: [.network: true, .mobileVitals: false, .custom: false, .errors: false,
                               .userActions: false, .anr: false, .lifeCycle: false],
            traceParentInHeader: [Keys.enable.rawValue: true]
        )
        let rum = CoralogixRum(options: options)
        instances.append(rum)
        let uploader = CapturingUploader()
        try XCTUnwrap(rum.coralogixExporter).spanUploader = uploader
        return (rum, uploader)
    }

    private func url(_ path: String) throws -> URL {
        try XCTUnwrap(URL(string: "https://\(ReinitURLProtocol.host)\(path)"))
    }

    private func makeSession(delegate: URLSessionDelegate? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReinitURLProtocol.self]
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        sessions.append(session)
        return session
    }

    private func completeRequest(_ url: URL, in session: URLSession) throws {
        let done = expectation(description: "request \(url.path)")
        session.dataTask(with: URLRequest(url: url)) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 5)
    }

    private func hybridReport(for url: URL, method: String = "GET") -> [String: Any] {
        [
            Keys.url.rawValue: url.absoluteString,
            Keys.host.rawValue: ReinitURLProtocol.host,
            Keys.method.rawValue: method,
            Keys.statusCode.rawValue: 200,
            Keys.duration.rawValue: 12,
            Keys.httpResponseBodySize.rawValue: 11,
            Keys.fragments.rawValue: url.path,
            Keys.schema.rawValue: "https"
        ]
    }

    /// The uploaded event for `url`, flushing `rum`'s batch processor until it appears.
    /// `method` tells the hybrid span apart from the native span for the same URL.
    private func event(for url: URL, in uploader: CapturingUploader, flushing rum: CoralogixRum,
                       method: String? = nil, timeout: TimeInterval = 8) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            rum.tracerProviderSdk?.forceFlush(timeout: 3)
            if let match = uploader.events.first(where: { event in
                guard let network = Self.networkContext(event),
                      network[Keys.url.rawValue] as? String == url.absoluteString else { return false }
                return method.map { network[Keys.method.rawValue] as? String == $0 } ?? true
            }) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return nil
    }

    private static func networkContext(_ event: [String: Any]) -> [String: Any]? {
        let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
        return cxRum?[Keys.networkRequestContext.rawValue] as? [String: Any]
    }

    private static func requestHeaders(_ network: [String: Any]) -> [String: String]? {
        let raw = network[Keys.requestHeaders.rawValue]
        if let dict = raw as? [String: Any] { return dict.compactMapValues { $0 as? String } }
        guard let json = (raw as? String)?.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        return dict.compactMapValues { $0 as? String }
    }
}
