//
//  NetworkWireSnapshotTests.swift
//  CoralogixRumTests
//
//  Golden-file gate on what the SDK sends for a network request. Each test drives one URLSession
//  path (or the hybrid bridge) against a URLProtocol stub, captures the uploaded event (cx_rum
//  envelope) and the OTLP JSON handed to `tracesExporter`, blanks the values that change from run
//  to run, and compares the result byte for byte with `WireSnapshots/NetworkWireSnapshot.json`.
//
//  The point is to catch any change in the wire format while the vendored OpenTelemetry copy is
//  refactored or replaced. A diff here is either a regression or an intended wire change; it is
//  never something to "fix" by re-recording without reading the diff.
//
//  Regenerating the golden file (only when the wire change is intended):
//
//      # SPM
//      CX_WIRE_SNAPSHOT_RECORD=1 swift test --filter NetworkWireSnapshotTests
//
//      # Xcode / simulator — xcodebuild forwards TEST_RUNNER_-prefixed variables to the test process
//      TEST_RUNNER_CX_WIRE_SNAPSHOT_RECORD=1 xcodebuild test -scheme Coralogix-Package \
//        -destination "platform=iOS Simulator,name=iPhone 16" \
//        -only-testing:CoralogixRumTests/NetworkWireSnapshotTests
//
//  In record mode every test rewrites its own section of the golden file and then fails on
//  purpose, so a record run can never pass CI by accident. Run once more without the variable,
//  then review the golden diff before committing it.
//
//  The golden file is read through `#filePath`, not a bundle resource: CocoaPods builds this
//  target from `test_spec`, which has no resource bundle.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

// MARK: - URLProtocol stub

private final class WireSnapshotURLProtocol: URLProtocol {
    static let host = "wire-snapshot.test"
    static let redirectPath = "/v1/redirect-start"
    static let redirectTarget = "/v1/redirect-final"
    static let body = Data(#"{"ok":true,"items":[1,2,3]}"#.utf8)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if url.path == Self.redirectPath,
           let target = URL(string: "https://\(Self.host)\(Self.redirectTarget)"),
           let redirect = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                          headerFields: ["Location": target.absoluteString, "Content-Length": "0"]) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: redirect)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                              headerFields: ["Content-Type": "application/json",
                                                             "Content-Length": "\(Self.body.count)"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Receives the response for the session-delegate path; no completion handler is involved.
private final class WireSnapshotSessionDelegate: NSObject, URLSessionDataDelegate {
    let completed: XCTestExpectation
    init(completed: XCTestExpectation) { self.completed = completed }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completed.fulfill()
    }
}

private final class WireCapturingUploader: SpanUploading {
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

// MARK: - Tests

final class NetworkWireSnapshotTests: XCTestCase {

    private static let recordMode = ProcessInfo.processInfo.environment["CX_WIRE_SNAPSHOT_RECORD"] == "1"

    private static let goldenURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("WireSnapshots/NetworkWireSnapshot.json")

    /// Placeholder written in place of every value that changes from run to run.
    private static let blank = "<volatile>"
    /// Written in place of the SDK's own version, so a version bump does not touch the golden
    /// file while the field itself stays pinned.
    private static let sdkVersionToken = "<sdk_version>"

    /// Trace context the hybrid test reports. Fixed inputs, so pinned even under an id key.
    private static let hybridTraceId = "0af7651916cd43dd8448eb211c80319c"
    private static let hybridSpanId = "b7ad6b7169203331"

    /// Keys whose values are ids, clocks, durations, or describe the machine running the test.
    /// Matched by key name anywhere in the cx_rum envelope, and by attribute key in OTLP
    /// key/value lists. Everything else is pinned verbatim. Every key here was seen to vary.
    private static let volatileKeys: Set<String> = [
        // ids, generated per span, session or SDK init
        "trace_id", "span_id", "traceId", "spanId", "sessionId", "session_id",
        "cx_rum.session_context.session_id", "fingerPrint",
        // clocks
        "timestamp", "startTime", "endTime", "duration", "start_time_unix_nano", "end_time_unix_nano",
        "session_creation_date", "cx_rum.session_context.session_creation_date",
        // the simulator running the test
        "osVersion", "cx_rum.session_context.osVersion", "device", "cx_rum.session_context.device",
        "device_name", "user_agent", "cx_rum.session_context.user_agent",
        // Reachability as NetworkManager saw it at init: races its first path update.
        "network_type",
    ]

    /// The connection type comes from a monitor created lazily on the first instrumented request,
    /// whose first path update arrives asynchronously: a request made right after it would read
    /// `unavailable` on any thread. Start it and let it settle before any test, so the recorded
    /// value does not depend on which test runs first.
    override class func setUp() {
        super.setUp()
        #if os(iOS) && !targetEnvironment(macCatalyst)
        _ = URLSessionLogger.netstatInjector
        if let probe = try? NetworkMonitor() {
            let deadline = Date().addingTimeInterval(3)
            while probe.getConnection() == .unavailable, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        Thread.sleep(forTimeInterval: 0.2)
        #endif
    }

    private var rum: CoralogixRum?
    private var uploader: WireCapturingUploader?
    private var session: URLSession?
    private let otlpLock = NSLock()
    private var otlpBatches: [[String: Any]] = []

    override func tearDownWithError() throws {
        session?.invalidateAndCancel()
        session = nil
        rum?.shutdown()
        rum = nil
        uploader = nil
        CoralogixRum.isInitialized = false
        CoralogixRum.mobileSDK = MobileSDK()
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        otlpLock.lock(); otlpBatches.removeAll(); otlpLock.unlock()
        try super.tearDownWithError()
    }

    // MARK: - Paths

    func test_completionHandler() throws {
        let url = try startAndMakeURL("/v1/completion-handler")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let done = expectation(description: "completion handler")
        try XCTUnwrap(session).dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 5)
        try assertWireSnapshot(named: "completion_handler", url: url)
    }

    func test_sessionDelegate() throws {
        let url = try startAndMakeURL("/v1/session-delegate")
        let done = expectation(description: "delegate didComplete")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WireSnapshotURLProtocol.self]
        let delegateSession = URLSession(configuration: config,
                                         delegate: WireSnapshotSessionDelegate(completed: done),
                                         delegateQueue: nil)
        session?.invalidateAndCancel()
        session = delegateSession
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        delegateSession.dataTask(with: request).resume()
        wait(for: [done], timeout: 5)
        try assertWireSnapshot(named: "session_delegate", url: url)
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    func test_asyncAwaitDataForRequest() async throws {
        // Initialised on the main thread as an app does; the request itself starts off it.
        let url = try await MainActor.run { try startAndMakeURL("/v1/async-await") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        _ = try await XCTUnwrap(session).data(for: request)
        try assertWireSnapshot(named: "async_await_data_for", url: url, nativeConnectionType: "unavailable")
    }

    func test_uploadTaskWithFrom() throws {
        let url = try startAndMakeURL("/v1/upload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let done = expectation(description: "upload")
        try XCTUnwrap(session).uploadTask(with: request, from: Data(#"{"name":"wire"}"#.utf8)) { _, _, _ in
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        try assertWireSnapshot(named: "upload_task_with_from", url: url)
    }

    func test_bareURLDataTask() throws {
        let url = try startAndMakeURL("/v1/bare-url")
        let done = expectation(description: "bare URL")
        try XCTUnwrap(session).dataTask(with: url) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 5)
        try assertWireSnapshot(named: "bare_url_data_task", url: url)
    }

    func test_redirect() throws {
        let url = try startAndMakeURL(WireSnapshotURLProtocol.redirectPath)
        var finalURL: URL?
        let done = expectation(description: "redirect")
        try XCTUnwrap(session).dataTask(with: URLRequest(url: url)) { _, response, _ in
            finalURL = response?.url
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(finalURL?.path, WireSnapshotURLProtocol.redirectTarget, "The stub must actually redirect")
        // The span is keyed on the request the app made, not the redirect target.
        try assertWireSnapshot(named: "redirect", url: url)
    }

    func test_hybridSetNetworkRequestContext() throws {
        let url = try startAndMakeURL("/v1/hybrid")
        try XCTUnwrap(rum).setNetworkRequestContext(dictionary: [
            Keys.url.rawValue: url.absoluteString,
            Keys.host.rawValue: WireSnapshotURLProtocol.host,
            Keys.method.rawValue: "POST",
            Keys.statusCode.rawValue: 201,
            Keys.statusText.rawValue: "Created",
            Keys.duration.rawValue: 42,
            Keys.httpResponseBodySize.rawValue: 27,
            Keys.fragments.rawValue: "/v1/hybrid",
            Keys.schema.rawValue: "https",
            Keys.traceId.rawValue: Self.hybridTraceId,
            Keys.spanId.rawValue: Self.hybridSpanId
        ])
        try assertWireSnapshot(named: "hybrid_set_network_request_context", url: url, nativeConnectionType: nil)
    }

    // MARK: - SDK setup

    private func startAndMakeURL(_ path: String) throws -> URL {
        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: UserContext(userId: "user-1", userName: "Wire Snapshot",
                                     userEmail: "wire@example.com", userMetadata: ["tier": "gold"]),
            environment: "wire-test",
            application: "WireSnapshotApp",
            version: "9.9.9",
            publicKey: "wire-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: ["suite": "wire-snapshot"],
            sessionSampleRate: 100,
            instrumentations: [.network: true, .mobileVitals: false, .custom: false, .errors: false,
                               .userActions: false, .anr: false, .lifeCycle: false],
            tracesExporter: { [weak self] data in
                guard let json = data.jsonData,
                      let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return }
                self?.otlpLock.lock()
                self?.otlpBatches.append(object)
                self?.otlpLock.unlock()
            }
        )
        let rum = CoralogixRum(options: options)
        self.rum = rum
        XCTAssertTrue(CoralogixRum.isInitialized)
        let uploader = WireCapturingUploader()
        try XCTUnwrap(rum.coralogixExporter).spanUploader = uploader
        self.uploader = uploader

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WireSnapshotURLProtocol.self]
        session = URLSession(configuration: config)

        return try XCTUnwrap(URL(string: "https://\(WireSnapshotURLProtocol.host)\(path)"))
    }

    // MARK: - Capture

    private struct Captured {
        let event: [String: Any]
        let otlpResource: Any
        let otlpScope: [String: Any]
        let otlpSpan: [String: Any]
    }

    private func capture(url: URL, timeout: TimeInterval = 8) -> Captured? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
            if let event = uploadedEvent(url: url), let otlp = otlpSpan(url: url) {
                return Captured(event: event, otlpResource: otlp.resource, otlpScope: otlp.scope, otlpSpan: otlp.span)
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return nil
    }

    private func uploadedEvent(url: URL) -> [String: Any]? {
        uploader?.events.first { event in
            let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
            let network = cxRum?[Keys.networkRequestContext.rawValue] as? [String: Any]
            return network?[Keys.url.rawValue] as? String == url.absoluteString
        }
    }

    private func otlpSpan(url: URL) -> (resource: Any, scope: [String: Any], span: [String: Any])? {
        otlpLock.lock(); defer { otlpLock.unlock() }
        for batch in otlpBatches {
            for resourceSpans in batch["resource_spans"] as? [[String: Any]] ?? [] {
                for scopeSpans in resourceSpans["scope_spans"] as? [[String: Any]] ?? [] {
                    for span in scopeSpans["spans"] as? [[String: Any]] ?? []
                    where Self.otlpString(span, SemanticAttributes.httpUrl.rawValue) == url.absoluteString {
                        return (resourceSpans["resource"] ?? [:], scopeSpans["scope"] as? [String: Any] ?? [:], span)
                    }
                }
            }
        }
        return nil
    }

    private static func otlpAttribute(_ span: [String: Any], _ key: String) -> [String: Any]? {
        let attributes = span["attributes"] as? [[String: Any]] ?? []
        return attributes.first { $0["key"] as? String == key }?["value"] as? [String: Any]
    }

    private static func otlpString(_ span: [String: Any], _ key: String) -> String? {
        otlpAttribute(span, key)?["string_value"] as? String
    }

    // MARK: - Assertions

    /// `nativeConnectionType` is the `network_connection_type` the request reports today; nil
    /// for the hybrid path, which reports none and is not a URLSession span.
    private func assertWireSnapshot(named name: String, url: URL, nativeConnectionType: String? = "wifi",
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let captured = try XCTUnwrap(capture(url: url),
                                     "No uploaded event and OTLP span for \(url) — the request was not instrumented",
                                     file: file, line: line)

        if let nativeConnectionType {
            assertExplicitContract(captured, url: url, connectionType: nativeConnectionType, file: file, line: line)
        }

        let snapshot: [String: Any] = [
            "cx_rum_event": Self.normalize(captured.event),
            "otlp": [
                "resource": Self.normalize(captured.otlpResource),
                "scope": Self.normalize(captured.otlpScope),
                "span": Self.normalize(captured.otlpSpan)
            ]
        ]
        let actual = try Self.serialize(snapshot)

        if Self.recordMode {
            try Self.record(name: name, snapshot: snapshot)
            XCTFail("Recorded wire snapshot '\(name)'. Re-run without CX_WIRE_SNAPSHOT_RECORD and review the golden diff.",
                    file: file, line: line)
            return
        }

        let golden = try Self.loadGolden()
        let expectedObject = try XCTUnwrap(golden[name],
                                           "Golden file has no '\(name)' section — record it (see the header of this file)",
                                           file: file, line: line)
        let expected = try Self.serialize(expectedObject)
        XCTAssertEqual(actual, expected,
                       "Wire snapshot '\(name)' changed. If the change is intended, re-record (see the header of this file) and review the diff.",
                       file: file, line: line)
    }

    /// Named, explicit claims on top of the golden comparison, so the most load-bearing fields
    /// fail with a readable message rather than a JSON diff.
    private func assertExplicitContract(_ captured: Captured, url: URL, connectionType: String,
                                        file: StaticString, line: UInt) {
        // Legacy (pre-1.x semconv) attribute keys the backend reads today.
        let span = captured.otlpSpan
        for key in ["http.method", "http.url", "http.target", "http.status_code",
                    "net.peer.name", "http.scheme", "http.response.body.size"] {
            XCTAssertNotNil(Self.otlpAttribute(span, key), "OTLP span lost legacy attribute '\(key)'",
                            file: file, line: line)
        }
        XCTAssertEqual(Self.otlpString(span, "http.url"), url.absoluteString, file: file, line: line)
        XCTAssertEqual(Self.otlpString(span, "net.peer.name"), WireSnapshotURLProtocol.host, file: file, line: line)
        XCTAssertEqual(Self.otlpString(span, "http.scheme"), "https", file: file, line: line)
        XCTAssertEqual(Self.otlpString(span, "http.target"), url.path, file: file, line: line)
        XCTAssertEqual(Self.otlpAttribute(span, "http.status_code")?["int_value"] as? String, "200", file: file, line: line)
        XCTAssertEqual(Self.otlpAttribute(span, "http.response.body.size")?["int_value"] as? String,
                       "\(WireSnapshotURLProtocol.body.count)", file: file, line: line)

        XCTAssertEqual(captured.otlpScope["name"] as? String, "NSURLSession", file: file, line: line)
        XCTAssertEqual(captured.otlpScope["version"] as? String, "0.0.1", file: file, line: line)

        // Records today's value, not the correct one: the connection type is read on the main
        // thread only, so a request started off it (async/await here) reports `unavailable`.
        // This expectation, and the golden file, change with the NetworkStatus fix.
        let deviceContext = ((captured.event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any])?[Keys.deviceContext.rawValue] as? [String: Any]
        XCTAssertEqual(deviceContext?[Keys.networkConnectionType.rawValue] as? String, connectionType,
                       "network_connection_type", file: file, line: line)
    }

    // MARK: - Normalization and golden I/O

    /// Replaces volatile values with a placeholder; keeps every key, so a key that appears or
    /// disappears still changes the snapshot.
    private static func normalize(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            // OTLP key/value pair: blank by attribute key.
            if let key = dict["key"] as? String, let child = dict["value"], dict.count == 2 {
                return ["key": key, "value": normalize(child, under: key)]
            }
            var result: [String: Any] = [:]
            for (key, child) in dict {
                result[key] = normalize(child, under: key)
            }
            return result
        case let array as [Any]:
            return array.map { normalize($0) }
        case let string as String where string == Global.sdk.rawValue:
            return sdkVersionToken
        default:
            return value
        }
    }

    private static func normalize(_ value: Any, under key: String) -> Any {
        guard volatileKeys.contains(key), !isFixedHybridId(value) else { return normalize(value) }
        return blank
    }

    private static func isFixedHybridId(_ value: Any) -> Bool {
        let string = (value as? String) ?? ((value as? [String: Any])?["string_value"] as? String)
        return string == hybridTraceId || string == hybridSpanId
    }

    private static func serialize(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func loadGolden() throws -> [String: Any] {
        let data = try Data(contentsOf: goldenURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func record(name: String, snapshot: [String: Any]) throws {
        var golden = (try? loadGolden()) ?? [:]
        golden[name] = snapshot
        try FileManager.default.createDirectory(at: goldenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (serialize(golden) + "\n").write(to: goldenURL, atomically: true, encoding: .utf8)
    }
}
