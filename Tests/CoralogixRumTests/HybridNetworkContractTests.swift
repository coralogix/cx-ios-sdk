//
//  HybridNetworkContractTests.swift
//  Coralogix
//
//  Created by Coralogix DEV TEAM on 10/08/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

/// Pins the full hybrid network bridge contract: every key the Flutter/React Native plugins send
/// in `setNetworkRequestContext` must surface on the exported event — except `error_message`,
/// whose absence is itself part of the contract (see the complete-dictionary test). The
/// complete-dictionary test exists so that a key whose handling silently changes fails a test
/// instead of shipping — `status_text` was dropped for years before this suite existed.
final class HybridNetworkContractTests: XCTestCase {

    private var rum: CoralogixRum?
    private var capturedSpans: [SpanData] = []
    private let captureLock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        capturedSpans = []
        CoralogixExporter.testExportCallback = { [weak self] spans in
            self?.captureLock.lock()
            self?.capturedSpans.append(contentsOf: spans)
            self?.captureLock.unlock()
        }
    }

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        CoralogixRum.isInitialized = false
        CoralogixExporter.testExportCallback = nil
        captureLock.lock()
        capturedSpans.removeAll(keepingCapacity: false)
        captureLock.unlock()
        try super.tearDownWithError()
    }

    private func startSDK(ignoreErrors: [String]? = nil) {
        rum = CoralogixRum(options: CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: nil,
            environment: "test",
            application: "HybridContractTest",
            version: "1.0",
            publicKey: "test-key",
            ignoreErrors: ignoreErrors,
            sessionSampleRate: 100,
            debug: false
        ))
        XCTAssertTrue(CoralogixRum.isInitialized)
    }

    /// Flushes the processor and polls for the exported hybrid network span matching the URL.
    private func waitForNetworkSpan(urlContains: String, timeout: TimeInterval = 5) -> SpanData? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
            captureLock.lock()
            let span = capturedSpans.last { span in
                let type = span.attributes[Keys.eventType.rawValue]?.description ?? ""
                guard type.contains(CoralogixEventType.networkRequest.rawValue) else { return false }
                let url = span.attributes[SemanticAttributes.httpUrl.rawValue]?.description ?? ""
                return url.contains(urlContains)
            }
            captureLock.unlock()
            if let span { return span }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    // MARK: - Complete-contract test (every bridge key)

    /// The COMPLETE dictionary both plugins can send, end-to-end through the real span pipeline.
    /// Every field must be reflected on the exported `network_request_context` (or the trace-id
    /// resolution for the id pairs). A future bridge key that is sent but not consumed must be
    /// added here — this test is the contract.
    func testCompleteHybridDictionarySurvivesToExportedContext() throws {
        startSDK()
        let url = "https://example.com/contract/full"
        let dictionary: [String: Any] = [
            Keys.url.rawValue: url,
            Keys.host.rawValue: "example.com",
            Keys.method.rawValue: "POST",
            Keys.statusCode.rawValue: 404,
            Keys.statusText.rawValue: "Not Found",
            Keys.duration.rawValue: 350,
            Keys.httpResponseBodySize.rawValue: 2387,
            Keys.fragments.rawValue: "/contract/full",
            Keys.schema.rawValue: "https",
            Keys.customTraceId.rawValue: "custom-trace",
            Keys.customSpanId.rawValue: "custom-span",
            Keys.traceId.rawValue: "wire-trace",
            Keys.spanId.rawValue: "wire-span",
            Keys.requestHeaders.rawValue: ["X-Req": "req-value"],
            Keys.responseHeaders.rawValue: ["X-Res": "res-value"],
            Keys.requestPayload.rawValue: "{\"q\":1}",
            Keys.responsePayload.rawValue: "{\"error\":\"not found\"}",
            Keys.errorMessage.rawValue: "HTTP 404 returned for /contract/full"
        ]

        rum?.setNetworkRequestContext(dictionary: dictionary)

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/contract/full"),
                                 "Hybrid network span must be exported")
        let context = NetworkRequestContext(otel: span)

        XCTAssertEqual(context.url, url)
        XCTAssertEqual(context.host, "example.com")
        XCTAssertEqual(context.method, "POST")
        XCTAssertEqual(context.statusCode, 404)
        XCTAssertEqual(context.statusText, "Not Found",
                       "status_text must survive the bridge — it shipped empty for years")
        XCTAssertEqual(context.fragments, "/contract/full")
        XCTAssertEqual(context.schema, "https")
        XCTAssertEqual(context.responseContentLength, 2387)
        XCTAssertGreaterThanOrEqual(context.duration, 350)
        XCTAssertLessThan(context.duration, 850)
        XCTAssertEqual(context.requestHeaders?["X-Req"], "req-value")
        XCTAssertEqual(context.responseHeaders?["X-Res"], "res-value")
        XCTAssertEqual(context.requestPayload, "{\"q\":1}")
        XCTAssertEqual(context.responsePayload, "{\"error\":\"not found\"}")

        // Id pairs: the custom pair wins and is what the exporter reads back.
        let ids = Helper.getTraceAndSpanId(otel: span)
        XCTAssertEqual(ids.traceId, "custom-trace")
        XCTAssertEqual(ids.spanId, "custom-span")

        // 404 must mark the event's severity as error.
        XCTAssertEqual(span.attributes[Keys.severity.rawValue]?.description,
                       String(CoralogixLogSeverity.error.rawValue))

        let wire = context.getDictionary()
        XCTAssertEqual(wire[Keys.statusText.rawValue] as? String, "Not Found",
                       "status_text must survive to the wire dictionary")

        // `error_message` is deliberately NOT exported, although the bridge sends it (Flutter
        // always has; RN since its status-text fix): the browser SDK's wire schema owns the
        // contract, failure descriptions belong to error_context only, and neither Android nor
        // browser emit one in network_request_context. iOS must not become the only platform
        // that does. Emitting it in the future must be a deliberate cross-platform schema
        // decision — this assertion is the tripwire.
        XCTAssertNil(wire[Keys.errorMessage.rawValue],
                     "error_message must not appear in network_request_context (cross-platform schema)")
    }

    // MARK: - status_text

    func testStatusTextOKSurfacesInContext() throws {
        startSDK()
        rum?.setNetworkRequestContext(dictionary: [
            Keys.url.rawValue: "https://example.com/contract/status-ok",
            Keys.method.rawValue: "GET",
            Keys.statusCode.rawValue: 200,
            Keys.statusText.rawValue: "OK"
        ])

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/contract/status-ok"))
        XCTAssertEqual(NetworkRequestContext(otel: span).statusText, "OK")
    }

    /// Old-plugin / native-path compatibility: without the bridge attribute the context keeps
    /// the span-status fallback — the native URLSession path is untouched by this change.
    func testMissingStatusTextFallsBackToSpanStatus() {
        let span = MockSpanData(
            attributes: [SemanticAttributes.httpUrl.rawValue: AttributeValue("https://example.com")],
            startTime: Date(), endTime: Date(),
            spanId: "s", traceId: "t", name: "n", kind: 2
        )
        span.statusText = "native-status"

        XCTAssertEqual(NetworkRequestContext(otel: span).statusText, "native-status",
                       "Without a bridge status_text attribute, getStatusText() must be used as before")
    }

    /// An empty bridge status_text (Flutter failure path sends "") must not shadow the fallback.
    func testEmptyStatusTextAttributeUsesFallback() {
        let span = MockSpanData(
            attributes: [Keys.statusText.rawValue: AttributeValue("")],
            startTime: Date(), endTime: Date(),
            spanId: "s", traceId: "t", name: "n", kind: 2
        )
        span.statusText = "fallback"

        XCTAssertEqual(NetworkRequestContext(otel: span).statusText, "fallback")
    }

    // MARK: - error_message (deliberately not exported)

    /// A failed request (Flutter catch path: status_code 0, error_message set) is exported as a
    /// network event WITHOUT the failure description — and, because the bridge value never
    /// reaches any span attribute, it cannot engage the exporter's ignoreErrors filter either:
    /// the event survives even when the message matches an ignoreErrors pattern.
    func testBridgeErrorMessageIsAcceptedButNeverExported() throws {
        startSDK(ignoreErrors: ["SocketException.*"])
        rum?.setNetworkRequestContext(dictionary: [
            Keys.url.rawValue: "https://example.com/contract/failure",
            Keys.method.rawValue: "GET",
            Keys.statusCode.rawValue: 0,
            Keys.statusText.rawValue: "",
            Keys.errorMessage.rawValue: "SocketException: Connection refused"
        ])

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/contract/failure"),
                                 "The failed request must still export as a network event")
        XCTAssertNil(span.attributes[Keys.errorMessage.rawValue],
                     "The bridge error_message must not be copied onto any span attribute")
        XCTAssertNil(NetworkRequestContext(otel: span).getDictionary()[Keys.errorMessage.rawValue],
                     "error_message must not appear in network_request_context (cross-platform schema)")

        // And the exporter's ignoreErrors filter keeps the span (nothing to match against).
        let exporter = try XCTUnwrap(rum?.coralogixExporter)
        XCTAssertTrue(exporter.shouldFilterIgnoreError(span: span))
    }
}
