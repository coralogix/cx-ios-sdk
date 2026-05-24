//
//  WireFormatTests.swift
//
//
//  Created by Coralogix DEV TEAM on 20/05/2026.
//
//  Pins the exact dict shape each MetricsManager / detector emits. The
//  EventReporter / MetricsCollector refactor (CX-40573) must preserve these
//  shapes byte-for-byte — these tests are the contract.
//
//  Three layers, in order:
//   1. Schema pins — key set + leaf type for each statsDictionary() and
//      the MetricsManager.sendMobileVitals() aggregate.
//   2. Round-trip — [String: Any] -> [VitalsMetric] -> toDictionary() is
//      byte-identical to the legacy payload.
//   3. End-to-end — protocol path produces the same JSON as the closure
//      path, both for sendMobileVitals() and for ANR.
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

    // MARK: - MetricsManager.sendMobileVitals() aggregate pin

    func testMetricsManager_sendMobileVitals_aggregateSchema_allDetectorsActive() {
        let manager = MetricsManager()
        // Wire up all detectors so the aggregate dict reaches its maximum shape.
        manager.cpuDetector = CPUDetector()
        manager.memoryDetector = MemoryDetector()
        manager.slowFrozenFramesDetector = SlowFrozenFramesDetector()
        manager.fpsDetector.isRunning = true  // FPS is only included when its detector is running

        var captured: [String: Any]?
        manager.metricsManagerClosure = { dict in captured = dict }

        manager.sendMobileVitals()

        guard let dict = captured else {
            XCTFail("metricsManagerClosure was not invoked")
            return
        }

        XCTAssertEqual(schema(dict), [
            "cpu.cpu_usage.avg: Double",
            "cpu.cpu_usage.max: Double",
            "cpu.cpu_usage.min: Double",
            "cpu.cpu_usage.p95: Double",
            "cpu.cpu_usage.units: String",
            "cpu.main_thread_cpu_time.avg: Double",
            "cpu.main_thread_cpu_time.max: Double",
            "cpu.main_thread_cpu_time.min: Double",
            "cpu.main_thread_cpu_time.p95: Double",
            "cpu.main_thread_cpu_time.units: String",
            "cpu.total_cpu_time.avg: Double",
            "cpu.total_cpu_time.max: Double",
            "cpu.total_cpu_time.min: Double",
            "cpu.total_cpu_time.p95: Double",
            "cpu.total_cpu_time.units: String",
            "fps.avg: Double",
            "fps.max: Double",
            "fps.min: Double",
            "fps.p95: Double",
            "fps.units: String",
            "memory.footprint_memory.avg: Double",
            "memory.footprint_memory.max: Double",
            "memory.footprint_memory.min: Double",
            "memory.footprint_memory.p95: Double",
            "memory.footprint_memory.units: String",
            "memory.memory_utilization.avg: Double",
            "memory.memory_utilization.max: Double",
            "memory.memory_utilization.min: Double",
            "memory.memory_utilization.p95: Double",
            "memory.memory_utilization.units: String",
            "memory.resident_memory.avg: Double",
            "memory.resident_memory.max: Double",
            "memory.resident_memory.min: Double",
            "memory.resident_memory.p95: Double",
            "memory.resident_memory.units: String",
            "slow_frozen.frozen_frames.avg: Double",
            "slow_frozen.frozen_frames.max: Double",
            "slow_frozen.frozen_frames.min: Double",
            "slow_frozen.frozen_frames.p95: Double",
            "slow_frozen.frozen_frames.units: String",
            "slow_frozen.slow_frames.avg: Double",
            "slow_frozen.slow_frames.max: Double",
            "slow_frozen.slow_frames.min: Double",
            "slow_frozen.slow_frames.p95: Double",
            "slow_frozen.slow_frames.units: String"
        ])
    }

    func testMetricsManager_sendMobileVitals_skipsEmptyPayload() {
        // Guard against silent regression: when no detector is attached and
        // FPS isn't running, sendMobileVitals() must NOT call the closure.
        let manager = MetricsManager()
        var callCount = 0
        manager.metricsManagerClosure = { _ in callCount += 1 }
        manager.sendMobileVitals()
        XCTAssertEqual(callCount, 0, "Empty vitals payload must not be sent")
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

    // MARK: - End-to-end: protocol path emits the same bytes as the closure path

    func testMetricsManager_protocolPath_equalsClosurePath_endToEnd() throws {
        // Run sendMobileVitals() twice with identical state — first via the
        // deprecated closure, then via the new MetricsCollector — and assert
        // the captured dicts serialize to the same JSON.

        let closureDict = try captureSendMobileVitals(useProtocolPath: false)
        let protocolDict = try captureSendMobileVitals(useProtocolPath: true)

        XCTAssertEqual(try jsonString(closureDict), try jsonString(protocolDict),
                       "Protocol path must produce the same bytes as the closure path")
    }

    private func captureSendMobileVitals(useProtocolPath: Bool) throws -> [String: Any] {
        let manager = MetricsManager()
        manager.cpuDetector = CPUDetector()
        manager.memoryDetector = MemoryDetector()
        manager.slowFrozenFramesDetector = SlowFrozenFramesDetector()
        manager.fpsDetector.isRunning = true

        var captured: [String: Any]?
        if useProtocolPath {
            manager.metricsCollector = RecordingMetricsCollector { dict in captured = dict }
        } else {
            manager.metricsManagerClosure = { dict in captured = dict }
        }

        manager.sendMobileVitals()
        return try XCTUnwrap(captured, "sendMobileVitals did not emit on \(useProtocolPath ? "protocol" : "closure") path")
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

/// Records the `[VitalsMetric]` batch and re-emits it as the legacy dict
/// shape so the wire-format equivalence tests can compare bytes against
/// the closure path. Lives in the test target only; production uses
/// `SpanMetricsCollector`.
private struct RecordingMetricsCollector: MetricsCollector {
    let onDict: ([String: Any]) -> Void
    func collect(_ metrics: [VitalsMetric]) {
        guard !metrics.isEmpty else { return }
        onDict(metrics.toDictionary())
    }
}

/// Records a `TelemetryEvent` for assertions. Test-target only.
private struct RecordingEventReporter: EventReporter {
    let onEvent: (TelemetryEvent) -> Void
    func report(_ event: TelemetryEvent) {
        onEvent(event)
    }
}
