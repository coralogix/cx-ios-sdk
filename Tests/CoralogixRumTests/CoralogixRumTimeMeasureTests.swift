//
//  CoralogixRumTimeMeasureTests.swift
//
//  End-to-end coverage for `startTimeMeasure` / `endTimeMeasure` (CX-28920 /
//  CX-40509). Drives the public API on `CoralogixRum`, force-flushes the
//  BatchSpanProcessor, and inspects the encoded CxSpan dict that lands on the
//  spanUploader — verifying both the payload shape (event_type =
//  custom-measurement, cx_rum.custom_measurement_context { name, value }) and
//  label merging (start wins on collision; labels live at cx_rum top level,
//  not nested under custom_measurement_context).
//
//  Reference: tech-debt/CX-28920_custom_time_measurement_api.md §3.6 + §6
//  (cases 9, 10, 11).
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class CoralogixRumTimeMeasureTests: XCTestCase {

    private var rum: CoralogixRum?
    private var mockUploader: TimeMeasureMockUploader!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Static SDK state can leak from a prior test that did not tear down cleanly.
        CoralogixRum.isInitialized = false
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        mockUploader = TimeMeasureMockUploader()
    }

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        CoralogixRum.isInitialized = false
        mockUploader = nil
        try super.tearDownWithError()
    }

    // MARK: - Case 9: labels merging + payload shape

    func testCase9_labels_startWinsOnCollision_andLandAtCxRumTopLevel() throws {
        try startRumWithMockUploader(sdkLabels: ["a": "options", "b": "options"])

        rum?.startTimeMeasure(name: "myTimer", labels: ["a": "start", "c": "start"])
        Thread.sleep(forTimeInterval: 0.02)
        rum?.endTimeMeasure(name: "myTimer")
        try forceFlush()

        let cxRum = try XCTUnwrap(
            mockUploader.customMeasurementSpans().first,
            "Should have captured exactly one custom-measurement span."
        )

        // Payload shape: event_type == custom-measurement
        let eventContext = try XCTUnwrap(cxRum[Keys.eventContext.rawValue] as? [String: Any])
        XCTAssertEqual(eventContext[Keys.type.rawValue] as? String,
                       CoralogixEventType.customMeasurement.rawValue,
                       "Span should carry event_type = custom-measurement.")

        // Payload shape: custom_measurement_context contains { name, value }
        let measurementContext = try XCTUnwrap(
            cxRum[Keys.customMeasurementContext.rawValue] as? [String: Any],
            "custom_measurement_context should exist under cx_rum."
        )
        XCTAssertEqual(measurementContext[Keys.name.rawValue] as? String, "myTimer")
        let value = try XCTUnwrap(measurementContext[Keys.value.rawValue] as? Double,
                                  "value should be present as Double.")
        XCTAssertGreaterThan(value, 0, "value should be a positive duration in milliseconds.")

        // Label merging: start labels override SDK labels on collision; both pools
        // contribute non-colliding keys.
        let labels = try XCTUnwrap(cxRum[Keys.labels.rawValue] as? [String: Any],
                                   "Merged labels should appear at cx_rum top level.")
        XCTAssertEqual(labels["a"] as? String, "start",
                       "On key collision, start-time labels must win over SDK-level labels.")
        XCTAssertEqual(labels["b"] as? String, "options",
                       "SDK-only labels are preserved.")
        XCTAssertEqual(labels["c"] as? String, "start",
                       "Start-only labels are included.")

        // Labels live at the cx_rum top level, NOT nested under custom_measurement_context
        XCTAssertNil(measurementContext[Keys.labels.rawValue],
                     "labels must not be nested under custom_measurement_context.")
        XCTAssertNil(measurementContext[Keys.customLabels.rawValue],
                     "custom_labels must not be nested under custom_measurement_context.")
    }

    // MARK: - Case 10: SDK not initialized — both calls are no-ops

    func testCase10_sdkNotInitialized_startAndEnd_areNoOp() throws {
        try startRumWithMockUploader()
        rum?.shutdown() // isInitialized → false

        // Both calls must be no-ops; neither should reach the tracker nor emit a span.
        rum?.startTimeMeasure(name: "x", labels: nil)
        rum?.endTimeMeasure(name: "x")
        try forceFlush()

        XCTAssertTrue(mockUploader.customMeasurementSpans().isEmpty,
                      "No custom-measurement spans should be emitted when the SDK is not initialized.")
    }

    // MARK: - Case 11: shutdown mid-measurement

    func testCase11_shutdownMidMeasurement_endIsNoOp() throws {
        try startRumWithMockUploader()

        rum?.startTimeMeasure(name: "a", labels: nil)
        rum?.shutdown() // teardown clears the tracker; isInitialized → false

        // end after shutdown must be a no-op — neither the guard nor the (now nil)
        // tracker reference is allowed to crash or emit a span.
        rum?.endTimeMeasure(name: "a")
        try forceFlush()

        XCTAssertTrue(mockUploader.customMeasurementSpans().isEmpty,
                      "No custom-measurement spans should be emitted when end fires after shutdown.")
    }

    // MARK: - Helpers

    private func startRumWithMockUploader(sdkLabels: [String: Any]? = nil) throws {
        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: nil,
            environment: "test",
            application: "TestApp",
            version: "1.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: sdkLabels,
            sessionSampleRate: 100,
            debug: false
        )
        rum = CoralogixRum(options: options)
        XCTAssertTrue(CoralogixRum.isInitialized, "Sanity check: rum should initialize.")
        // Swap the real uploader with the mock so test runs stay offline and we can
        // inspect the encoded `[[String: Any]]` payloads downstream of encodeSpans.
        // Unwrap explicitly so a nil exporter fails the test loudly instead of
        // silently skipping the mock injection.
        let exporter = try XCTUnwrap(rum?.coralogixExporter,
                                     "coralogixExporter must exist to inject the mock uploader.")
        exporter.spanUploader = mockUploader
    }

    /// Drain the BatchSpanProcessor and give the spanUploader time to receive.
    /// Same shape used by `GlobalSpanPropagationIntegrationTests.forceFlush()`.
    /// `TracerProviderSdk.forceFlush(timeout:)` returns Void in this SDK version,
    /// so there's no result to assert on — but the cast itself must succeed,
    /// otherwise the flush silently no-ops and tests would race the batcher.
    private func forceFlush() throws {
        let provider = try XCTUnwrap(
            OpenTelemetry.instance.tracerProvider as? TracerProviderSdk,
            "OpenTelemetry.instance.tracerProvider must be a TracerProviderSdk in this test environment."
        )
        provider.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.6)
    }
}

// MARK: - Test Doubles

/// Captures the encoded `[[String: Any]]` batches the exporter would normally upload.
/// Each `upload(_:endPoint:)` call becomes one batch; `allSpans` flattens them in order.
/// Filtering by event_type lets cases assert only on `custom-measurement` spans and
/// ignore the SDK's own init span (event_type = internal-key).
private final class TimeMeasureMockUploader: SpanUploading {
    private let lock = NSLock()
    private var batches: [[[String: Any]]] = []

    func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
        lock.lock()
        batches.append(spans)
        lock.unlock()
        return .success
    }

    var allSpans: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return batches.flatMap { $0 }
    }

    /// Returns the `cx_rum` dict for every span whose `event_context.type` is
    /// `custom-measurement`. Empty when no such span was uploaded.
    func customMeasurementSpans() -> [[String: Any]] {
        return allSpans.compactMap { span -> [String: Any]? in
            guard let cxRum = Self.cxRum(in: span),
                  let eventContext = cxRum[Keys.eventContext.rawValue] as? [String: Any],
                  let type = eventContext[Keys.type.rawValue] as? String,
                  type == CoralogixEventType.customMeasurement.rawValue else {
                return nil
            }
            return cxRum
        }
    }

    /// Encoded CxSpan envelope is `{ "text": { "cx_rum": { ... } } }` — same shape T5's
    /// `EventTypeCapture` walks for the hybrid `beforeSendCallBack` path.
    private static func cxRum(in span: [String: Any]) -> [String: Any]? {
        guard let text = span[Keys.text.rawValue] as? [String: Any],
              let cxRum = text[Keys.cxRum.rawValue] as? [String: Any] else {
            return nil
        }
        return cxRum
    }
}
