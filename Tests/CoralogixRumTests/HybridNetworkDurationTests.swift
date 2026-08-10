//
//  HybridNetworkDurationTests.swift
//  Coralogix
//
//  Created by Coralogix DEV TEAM on 10/08/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

/// Hybrid layers (Flutter/React Native) measure network requests themselves and report `duration`
/// in milliseconds through the bridge. Native must honor it: the span is back-dated by the reported
/// duration so the emitted `network_request_context.duration` (span end − start) equals the measured
/// value. Previously the key was never read and every hybrid request shipped with a constant 1 ms.
final class HybridNetworkDurationTests: XCTestCase {

    // MARK: - coerceToDurationMs: coercion matrix

    /// Platform channels deliver numbers as Int, Int64, Double, or NSNumber depending on the
    /// platform and value size; some bridges stringify. All numeric shapes must coerce.
    func testCoercionAcceptsAllNumericShapes() {
        XCTAssertEqual(CoralogixRum.coerceToDurationMs(350), 350.0, "Int must coerce")
        XCTAssertEqual(CoralogixRum.coerceToDurationMs(Int64(350)), 350.0, "Int64 must coerce")
        XCTAssertEqual(CoralogixRum.coerceToDurationMs(350.5), 350.5, "Double must coerce")
        XCTAssertEqual(CoralogixRum.coerceToDurationMs(NSNumber(value: 350)), 350.0, "NSNumber must coerce")
        XCTAssertEqual(CoralogixRum.coerceToDurationMs("350"), 350.0, "Integer string must coerce")
        XCTAssertEqual(CoralogixRum.coerceToDurationMs("350.5"), 350.5, "Decimal string must coerce")
    }

    /// A zero or fractional duration is a legitimate sub-millisecond measurement, not an
    /// absent value. (The export pipeline floors emitted durations at 1 ms for every event
    /// type; the coercion itself must not reject the measurement.)
    func testCoercionAcceptsZeroAndSubMillisecond() {
        XCTAssertEqual(CoralogixRum.coerceToDurationMs(0), 0.0)
        XCTAssertEqual(CoralogixRum.coerceToDurationMs(0.4), 0.4)
    }

    /// Durations above 24h are bridge bugs; back-dating that far would overflow the UInt64
    /// nanosecond conversions in the export pipeline, so they must be treated as absent.
    /// The boundary itself is a valid (if absurd) measurement.
    func testCoercionEnforcesUpperBound() {
        XCTAssertEqual(CoralogixRum.coerceToDurationMs(CoralogixRum.maxHybridDurationMs),
                       CoralogixRum.maxHybridDurationMs, "The 24h boundary itself is accepted")
        XCTAssertNil(CoralogixRum.coerceToDurationMs(CoralogixRum.maxHybridDurationMs + 1),
                     "Just above the bound must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs(1e30), "Huge Double must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs(Double.greatestFiniteMagnitude),
                     "greatestFiniteMagnitude must be absent — it would trap UInt64 conversion at export")
    }

    /// Negative, non-numeric, non-finite, or missing values mean "no duration reported" —
    /// the handler must fall back to today's zero-length-span behavior, never crash or back-date
    /// into the future.
    func testCoercionRejectsInvalidValues() {
        XCTAssertNil(CoralogixRum.coerceToDurationMs(nil), "Missing value must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs(-1), "Negative Int must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs(-0.5), "Negative Double must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs("-350"), "Negative string must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs("abc"), "Non-numeric string must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs(""), "Empty string must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs("nan"), "NaN string must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs("inf"), "Infinite string must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs(Double.nan), "NaN must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs(Double.infinity), "Infinity must be absent")
        XCTAssertNil(CoralogixRum.coerceToDurationMs(true), "Bool must be absent (bridges to NSNumber 1)")
        XCTAssertNil(CoralogixRum.coerceToDurationMs([350]), "Array must be absent")
    }

    // MARK: - End-to-end through the handler and the real span pipeline

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
        rum = CoralogixRum(options: CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: nil,
            environment: "test",
            application: "HybridDurationTest",
            version: "1.0",
            publicKey: "test-key",
            sessionSampleRate: 100,
            debug: false
        ))
        XCTAssertTrue(CoralogixRum.isInitialized)
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

    private func hybridPayload(url: String, extra: [String: Any] = [:]) -> [String: Any] {
        var dict: [String: Any] = [
            Keys.url.rawValue: url,
            Keys.host.rawValue: "example.com",
            Keys.method.rawValue: "GET",
            Keys.statusCode.rawValue: 200,
            Keys.schema.rawValue: "https"
        ]
        extra.forEach { dict[$0.key] = $0.value }
        return dict
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

    /// The core fix: a bridge payload reporting `duration: 350` (ms) must produce an exported span
    /// whose end − start is ~350 ms, and a `network_request_context.duration` of ~350 — not 1.
    func testReportedDurationSurvivesToExportedSpanAndContext() throws {
        let url = "https://example.com/hybrid/duration-350"
        rum?.setNetworkRequestContext(dictionary: hybridPayload(url: url, extra: [
            Keys.duration.rawValue: 350
        ]))

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/hybrid/duration-350"),
                                 "Hybrid network span must be exported")

        let delta = span.endTime.timeIntervalSince(span.startTime)
        XCTAssertGreaterThanOrEqual(delta, 0.349,
                                    "Span end − start must reflect the reported 350 ms duration")
        XCTAssertLessThan(delta, 0.85,
                          "Span duration must not drift far beyond the reported value (handler overhead only)")

        let context = NetworkRequestContext(otel: span)
        XCTAssertGreaterThanOrEqual(context.duration, 350,
                                    "network_request_context.duration must report the measured duration, not 1 ms")
        XCTAssertLessThan(context.duration, 850)
    }

    /// The coercion is wired into the handler: a stringified duration (some bridges stringify
    /// numbers) must be honored the same as a numeric one.
    func testStringDurationIsHonoredByHandler() throws {
        let url = "https://example.com/hybrid/duration-string"
        rum?.setNetworkRequestContext(dictionary: hybridPayload(url: url, extra: [
            Keys.duration.rawValue: "350"
        ]))

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/hybrid/duration-string"))
        let delta = span.endTime.timeIntervalSince(span.startTime)
        XCTAssertGreaterThanOrEqual(delta, 0.349)
        XCTAssertLessThan(delta, 0.85)
    }

    /// Event-timestamp semantics, pinned as a documented decision: honoring the duration works by
    /// back-dating the span START to the request start — the span end (the event's timestamp)
    /// stays "now". The span's time range therefore covers the actual request window.
    func testBackDatingShiftsSpanStartToRequestStart() throws {
        let url = "https://example.com/hybrid/backdated"
        let beforeCall = Date()
        rum?.setNetworkRequestContext(dictionary: hybridPayload(url: url, extra: [
            Keys.duration.rawValue: 350
        ]))

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/hybrid/backdated"))

        XCTAssertLessThan(span.startTime, beforeCall,
                          "Span start must be back-dated into the past (the request's actual start)")
        let backdate = beforeCall.timeIntervalSince(span.startTime)
        XCTAssertLessThan(abs(backdate - 0.35), 0.25,
                          "Span start must sit ~350 ms before the report call")
        XCTAssertGreaterThanOrEqual(span.endTime, beforeCall,
                                    "Span end (the event timestamp) must remain the time of the report call")
    }

    /// Old-plugin compatibility: a payload without `duration` behaves exactly as today — the span
    /// starts and ends at the moment of the call (a point-in-time event).
    func testMissingDurationKeepsZeroLengthSpan() throws {
        let url = "https://example.com/hybrid/no-duration"
        rum?.setNetworkRequestContext(dictionary: hybridPayload(url: url))

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/hybrid/no-duration"))
        let delta = span.endTime.timeIntervalSince(span.startTime)
        XCTAssertLessThan(delta, 0.2,
                          "Without a reported duration the span must not be back-dated")
    }

    /// An invalid duration (garbage from a broken bridge) must degrade to the missing-key path,
    /// never crash or produce a bogus time range.
    func testGarbageDurationFallsBackToZeroLengthSpan() throws {
        let url = "https://example.com/hybrid/garbage-duration"
        rum?.setNetworkRequestContext(dictionary: hybridPayload(url: url, extra: [
            Keys.duration.rawValue: "not-a-number"
        ]))

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/hybrid/garbage-duration"))
        let delta = span.endTime.timeIntervalSince(span.startTime)
        XCTAssertLessThan(delta, 0.2)
    }

    /// Regression: an extreme duration must not back-date the span into a range that overflows
    /// the UInt64 nanosecond conversions during export (a host-app crash). It degrades to the
    /// missing-key path — a zero-length span that exports cleanly end-to-end.
    func testExtremeDurationDoesNotCrashExport() throws {
        let url = "https://example.com/hybrid/extreme-duration"
        rum?.setNetworkRequestContext(dictionary: hybridPayload(url: url, extra: [
            Keys.duration.rawValue: Double.greatestFiniteMagnitude
        ]))

        let span = try XCTUnwrap(waitForNetworkSpan(urlContains: "/hybrid/extreme-duration"),
                                 "Span must export (not crash) despite the absurd duration")
        let delta = span.endTime.timeIntervalSince(span.startTime)
        XCTAssertLessThan(delta, 0.2, "Extreme duration must be discarded, not back-dated")

        // The full context computation must also survive and stay sane.
        let context = NetworkRequestContext(otel: span)
        XCTAssertLessThan(context.duration, 1000)
    }
}
