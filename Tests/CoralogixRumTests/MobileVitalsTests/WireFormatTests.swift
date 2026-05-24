//
//  WireFormatTests.swift
//
//
//  Created by Coralogix DEV TEAM on 20/05/2026.
//
//  Pins the exact dict shape each detector emits. The EventReporter /
//  MetricsCollector refactor (CX-40573 / CX-43340) must preserve these
//  shapes byte-for-byte — these tests are the contract.
//
//  Four layers, in order:
//   1. Schema pins — key set + leaf type for each detector's
//      statsDictionary().
//   2. Per-detector self-push (CX-43340) — each detector, wired with a
//      MetricsCollector, emits exactly one VitalsMetric on flush() with
//      its category key and the same payload shape it produced before
//      the migration. ANRDetector emits one ANRErrorEvent through its
//      EventReporter on handleANR().
//   3. Round-trip — [String: Any] -> [VitalsMetric] -> toDictionary() is
//      byte-identical to the legacy payload (still used by the
//      cold/warm/MetricKit path through MetricsManager.emitMetricKitPayload).
//   4. End-to-end ANR — protocol path produces the same fields as the
//      legacy closure path (closure removal is out of scope per CX-43340).
//
//  We pin *key set and leaf type* at every nesting level, not the float
//  values (which depend on live stats and would be flaky).

import XCTest
import CoralogixInternal
@testable import Coralogix

final class WireFormatTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a sorted list of `"path: <typeLabel>"` entries describing the
    /// nested dict structure. Dict children recurse; leaves render their type.
    private func schema(_ value: Any, prefix: String = "") -> [String] {
        if let dict = value as? [String: Any] {
            return dict.keys.sorted().flatMap { key -> [String] in
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                return schema(dict[key] as Any, prefix: path)
            }
        }
        return ["\(prefix): \(typeLabel(of: value))"]
    }

    /// Coarse type label so the snapshot survives Int vs Int64 differences
    /// from JSONSerialization, but still catches String vs numeric swaps.
    private func typeLabel(of value: Any) -> String {
        switch value {
        case is String: return "String"
        case is Bool:   return "Bool"
        case is Int, is Int32, is Int64, is UInt, is UInt32, is UInt64: return "Int"
        case is Double, is Float, is CGFloat: return "Double"
        default: return String(describing: Swift.type(of: value))
        }
    }

    // MARK: - Per-detector statsDictionary() pins

    func testCPUDetector_statsDictionary_schema() {
        let detector = CPUDetector()
        XCTAssertEqual(schema(detector.statsDictionary()), [
            "cpu_usage.avg: Double",
            "cpu_usage.max: Double",
            "cpu_usage.min: Double",
            "cpu_usage.p95: Double",
            "cpu_usage.units: String",
            "main_thread_cpu_time.avg: Double",
            "main_thread_cpu_time.max: Double",
            "main_thread_cpu_time.min: Double",
            "main_thread_cpu_time.p95: Double",
            "main_thread_cpu_time.units: String",
            "total_cpu_time.avg: Double",
            "total_cpu_time.max: Double",
            "total_cpu_time.min: Double",
            "total_cpu_time.p95: Double",
            "total_cpu_time.units: String"
        ])
    }

    func testMemoryDetector_statsDictionary_schema() {
        let detector = MemoryDetector()
        XCTAssertEqual(schema(detector.statsDictionary()), [
            "footprint_memory.avg: Double",
            "footprint_memory.max: Double",
            "footprint_memory.min: Double",
            "footprint_memory.p95: Double",
            "footprint_memory.units: String",
            "memory_utilization.avg: Double",
            "memory_utilization.max: Double",
            "memory_utilization.min: Double",
            "memory_utilization.p95: Double",
            "memory_utilization.units: String",
            "resident_memory.avg: Double",
            "resident_memory.max: Double",
            "resident_memory.min: Double",
            "resident_memory.p95: Double",
            "resident_memory.units: String"
        ])
    }

    func testSlowFrozenFramesDetector_statsDictionary_schema() {
        let detector = SlowFrozenFramesDetector()
        XCTAssertEqual(schema(detector.statsDictionary()), [
            "frozen_frames.avg: Double",
            "frozen_frames.max: Double",
            "frozen_frames.min: Double",
            "frozen_frames.p95: Double",
            "frozen_frames.units: String",
            "slow_frames.avg: Double",
            "slow_frames.max: Double",
            "slow_frames.min: Double",
            "slow_frames.p95: Double",
            "slow_frames.units: String"
        ])
    }

    func testFPSDetector_statsDictionary_schema() {
        let detector = FPSDetector()
        XCTAssertEqual(schema(detector.statsDictionary()), [
            "avg: Double",
            "max: Double",
            "min: Double",
            "p95: Double",
            "units: String"
        ])
    }

    // MARK: - Per-detector self-push (CX-43340)
    //
    // Each periodic detector, when constructed with a `MetricsCollector`,
    // emits exactly one `VitalsMetric` on `flush()` — the category key
    // plus the same payload shape `statsDictionary()` would produce.
    // These tests pin the contract that `MetricsManager.flushAll()` and
    // `NavigationInstrumentation` rely on.

    func testCPUDetector_flush_pushesOneMetricViaCollector() throws {
        let recorder = BatchRecordingCollector()
        let detector = CPUDetector(metricsCollector: recorder)

        detector.flush()

        let batch = try XCTUnwrap(recorder.batches.first, "flush() did not call collect()")
        XCTAssertEqual(recorder.batches.count, 1, "flush() must emit exactly one batch")
        XCTAssertEqual(batch.count, 1, "CPU flush must emit a single VitalsMetric")
        XCTAssertEqual(batch.first?.name, Keys.cpu.rawValue)
        let payload = try XCTUnwrap(batch.first?.payload as? [String: Any])
        XCTAssertEqual(schema(payload), schema(detector.statsDictionary()),
                       "CPU flush payload must match statsDictionary() schema")
    }

    func testMemoryDetector_flush_pushesOneMetricViaCollector() throws {
        let recorder = BatchRecordingCollector()
        let detector = MemoryDetector(metricsCollector: recorder)

        detector.flush()

        let batch = try XCTUnwrap(recorder.batches.first, "flush() did not call collect()")
        XCTAssertEqual(recorder.batches.count, 1)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.name, Keys.memory.rawValue)
        let payload = try XCTUnwrap(batch.first?.payload as? [String: Any])
        XCTAssertEqual(schema(payload), schema(detector.statsDictionary()))
    }

    func testSlowFrozenFramesDetector_flush_pushesOneMetricViaCollector() throws {
        let recorder = BatchRecordingCollector()
        let detector = SlowFrozenFramesDetector(metricsCollector: recorder)

        detector.flush()

        let batch = try XCTUnwrap(recorder.batches.first, "flush() did not call collect()")
        XCTAssertEqual(recorder.batches.count, 1)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.name, Keys.slowFrozen.rawValue)
        let payload = try XCTUnwrap(batch.first?.payload as? [String: Any])
        XCTAssertEqual(schema(payload), schema(detector.statsDictionary()))
    }

    func testFPSDetector_flush_pushesOneMetricViaCollector_whenRunning() throws {
        let recorder = BatchRecordingCollector()
        let detector = FPSDetector(metricsCollector: recorder)
        detector.isRunning = true   // FPS only emits while its display link is active

        detector.flush()

        let batch = try XCTUnwrap(recorder.batches.first, "flush() did not call collect()")
        XCTAssertEqual(recorder.batches.count, 1)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.name, MobileVitalsType.fps.stringValue)
        let payload = try XCTUnwrap(batch.first?.payload as? [String: Any])
        XCTAssertEqual(schema(payload), schema(detector.statsDictionary()))
    }

    func testFPSDetector_flush_skipsEmit_whenNotRunning() {
        // Preserves the legacy semantic: FPS is only included when its
        // display-link sampler is active (pre-CX-43340 this was an
        // `if fpsDetector.isRunning` gate in MetricsManager.sendMobileVitals).
        let recorder = BatchRecordingCollector()
        let detector = FPSDetector(metricsCollector: recorder)
        // detector.isRunning is false by default

        detector.flush()

        XCTAssertTrue(recorder.batches.isEmpty, "FPS must not emit when not running")
    }

    func testDetector_flush_isNoOp_whenNoCollectorWired() {
        // A detector with no metricsCollector silently drops the flush —
        // this is the legacy path for test code that constructs detectors
        // directly. No throw, no log spam, no closure path.
        CPUDetector().flush()
        MemoryDetector().flush()
        SlowFrozenFramesDetector().flush()
        let fps = FPSDetector()
        fps.isRunning = true
        fps.flush()
        // No assertion needed — the test asserts only that the calls return.
    }

    // MARK: - ANRDetector self-push (CX-43340)

    func testANRDetector_handleANR_pushesViaEventReporter_whenWired() throws {
        var captured: TelemetryEvent?
        let reporter = RecordingEventReporter { captured = $0 }
        let detector = ANRDetector(eventReporter: reporter)

        detector.handleANR()

        let event = try XCTUnwrap(captured as? ANRErrorEvent,
                                  "handleANR must emit an ANRErrorEvent through the protocol path")
        XCTAssertEqual(event.errorMessage, WireValues.anrErrorMessage.rawValue)
        XCTAssertEqual(event.errorType, WireValues.anrErrorType.rawValue)
    }

    func testANRDetector_handleANR_fallsBackToClosure_whenEventReporterNil() {
        // Backward-compat path: when no protocol sink is wired, handleANR
        // still routes through the legacy closure (out of scope to remove
        // per CX-43340; covered by 1.5b).
        var closureFired = false
        let detector = ANRDetector()
        detector.handleANRClosure = { closureFired = true }

        detector.handleANR()

        XCTAssertTrue(closureFired, "Closure path must still fire when eventReporter is nil")
    }

    // MARK: - Cold / Warm / MetricKit single-shot payload pins
    //
    // These three emit ad-hoc dicts (not via sendMobileVitals). The structures
    // are tiny and stable — pin them so a refactor can't quietly rename keys.

    func testColdDetector_payloadSchema() {
        // The cold payload shape (no good seam to drive it without UIApplication
        // notifications) — assert the constants the producer uses so any rename
        // forces a wire-format reckoning.
        XCTAssertEqual(MobileVitalsType.cold.stringValue, "cold")
        XCTAssertEqual(Keys.mobileVitalsUnits.rawValue, "units")
        XCTAssertEqual(Keys.value.rawValue, "value")
        XCTAssertEqual(MeasurementUnits.milliseconds.stringValue, "ms")
    }

    func testWarmDetector_payloadSchema() {
        XCTAssertEqual(MobileVitalsType.warm.stringValue, "warm")
        XCTAssertEqual(Keys.mobileVitalsUnits.rawValue, "units")
        XCTAssertEqual(Keys.value.rawValue, "value")
    }

    func testMetricKit_payloadSchema() {
        // Producer in MetricsManager.swift:256-260 emits:
        //   { metric_kit: { name: "<json-string>" } }
        XCTAssertEqual(Keys.metricKit.rawValue, "metric_kit")
        XCTAssertEqual(Keys.name.rawValue, "name")
    }

    // MARK: - Round-trip: dict → [VitalsMetric] → toDictionary() → dict
    //
    // Pins the contract the production `SpanMetricsCollector` relies on:
    // a dict shaped like the legacy `metricsManagerClosure` payload must
    // round-trip byte-identical through the new `[VitalsMetric]` value
    // type. `SpanMetricsCollector.collect` calls `toDictionary()` and
    // JSON-encodes the result onto a span attribute — so this property
    // is what guarantees wire compatibility.

    func testVitalsMetric_toDictionary_roundTripsLegacyDict() throws {
        let original: [String: Any] = [
            Keys.cpu.rawValue: [
                MobileVitalsType.cpuUsage.stringValue: [
                    Keys.mobileVitalsUnits.rawValue: MeasurementUnits.percentage.stringValue,
                    Keys.min.rawValue: 1.0,
                    Keys.max.rawValue: 9.0,
                    Keys.avg.rawValue: 4.5,
                    Keys.p95.rawValue: 8.5
                ]
            ],
            Keys.memory.rawValue: [
                MobileVitalsType.footprintMemory.stringValue: [
                    Keys.mobileVitalsUnits.rawValue: MeasurementUnits.megaBytes.stringValue,
                    Keys.min.rawValue: 50.0,
                    Keys.max.rawValue: 120.0,
                    Keys.avg.rawValue: 80.0,
                    Keys.p95.rawValue: 110.0
                ]
            ],
            MobileVitalsType.fps.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.fps.stringValue,
                Keys.min.rawValue: 30.0,
                Keys.max.rawValue: 60.0,
                Keys.avg.rawValue: 55.0,
                Keys.p95.rawValue: 59.0
            ]
        ]

        let metrics: [VitalsMetric] = original.map { (key, value) in
            VitalsMetric(name: key, payload: value as? [String: Any] ?? [:])
        }
        let rebuilt = metrics.toDictionary()

        XCTAssertEqual(try jsonString(original), try jsonString(rebuilt),
                       "Round-trip dict must be byte-identical to the legacy payload")
    }

    // MARK: - End-to-end ANR equivalence

    func testANR_protocolPath_equalsClosurePath_endToEnd() {
        // Capture (message, errorType) via the closure path…
        let viaClosure = captureANR(useProtocolPath: false)

        // …and capture the same fields from the typed ANRErrorEvent on the protocol path.
        let viaProtocol = captureANR(useProtocolPath: true)

        XCTAssertEqual(viaClosure?.message, viaProtocol?.message)
        XCTAssertEqual(viaClosure?.errorType, viaProtocol?.errorType)
        XCTAssertEqual(viaClosure?.message, WireValues.anrErrorMessage.rawValue)
        XCTAssertEqual(viaClosure?.errorType, WireValues.anrErrorType.rawValue)
    }

    private func captureANR(useProtocolPath: Bool) -> (message: String, errorType: String)? {
        let manager = MetricsManager()
        var captured: (message: String, errorType: String)?
        if useProtocolPath {
            manager.eventReporter = RecordingEventReporter { event in
                guard let anr = event as? ANRErrorEvent else { return }
                captured = (anr.errorMessage, anr.errorType)
            }
        } else {
            manager.anrErrorClosure = { msg, type in captured = (msg, type) }
        }
        manager.startANRMonitoring()
        manager.anrDetector?.handleANR()
        return captured
    }

    // MARK: - JSON helper

    /// Deterministic JSON serialization for dict equality.
    /// Uses `.sortedKeys` so dict ordering can't smuggle in a false positive.
    /// Throws on any serialization failure — never returns a sentinel — so a
    /// silently-broken payload can't make two failed-encode calls compare equal.
    private func jsonString(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        guard let str = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "WireFormatTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "JSON data was not valid UTF-8"])
        }
        return str
    }
}

// MARK: - Test doubles

/// Records each `collect(_:)` call as a separate batch so per-detector
/// self-push tests can assert both *what* was emitted and *how many
/// times*. Production uses `SpanMetricsCollector`.
///
/// A class (not struct) so callers can hold a single reference and
/// observe mutations from `flush()`.
private final class BatchRecordingCollector: MetricsCollector {
    var batches: [[VitalsMetric]] = []
    func collect(_ metrics: [VitalsMetric]) {
        batches.append(metrics)
    }
}

/// Records a `TelemetryEvent` for assertions. Test-target only.
private struct RecordingEventReporter: EventReporter {
    let onEvent: (TelemetryEvent) -> Void
    func report(_ event: TelemetryEvent) {
        onEvent(event)
    }
}
