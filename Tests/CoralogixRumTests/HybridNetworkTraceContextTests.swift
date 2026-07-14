//
//  HybridNetworkTraceContextTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 14/07/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

/// Hybrid (Flutter/React Native) network requests inject the `traceparent` on the wire from an upper
/// layer and report the ids they used to native. The exported RUM span must carry those same ids so it
/// stitches to the backend trace. These tests pin the resolution precedence and the end-to-end path
/// from the hybrid payload through to `Helper.getTraceAndSpanId` (what the exporter reads).
final class HybridNetworkTraceContextTests: XCTestCase {

    // MARK: - resolveHybridTraceContext precedence

    /// The active-custom-span pair wins when present, even if per-request wire ids are also supplied.
    func testCustomTraceContextPreferredOverWireIds() {
        let dict: [String: Any] = [
            Keys.customTraceId.rawValue: "custom-trace",
            Keys.customSpanId.rawValue: "custom-span",
            Keys.traceId.rawValue: "wire-trace",
            Keys.spanId.rawValue: "wire-span"
        ]

        let result = CoralogixRum.resolveHybridTraceContext(from: dict)

        XCTAssertEqual(result.traceId, "custom-trace")
        XCTAssertEqual(result.spanId, "custom-span")
    }

    /// The fix: for an ordinary request (no active custom span) the Dart/JS layer reports the wire ids
    /// under `traceId`/`spanId`. These must be honored — previously iOS dropped them.
    func testFallsBackToWireIdsWhenCustomAbsent() {
        let dict: [String: Any] = [
            Keys.traceId.rawValue: "wire-trace",
            Keys.spanId.rawValue: "wire-span"
        ]

        let result = CoralogixRum.resolveHybridTraceContext(from: dict)

        XCTAssertEqual(result.traceId, "wire-trace",
                       "Per-request wire traceId reported under 'traceId' must be used when customTraceId is absent")
        XCTAssertEqual(result.spanId, "wire-span")
    }

    /// Empty-string custom ids (native default when the JS layer omits them) must not shadow the wire ids.
    func testFallsBackToWireIdsWhenCustomAreEmptyStrings() {
        let dict: [String: Any] = [
            Keys.customTraceId.rawValue: "",
            Keys.customSpanId.rawValue: "",
            Keys.traceId.rawValue: "wire-trace",
            Keys.spanId.rawValue: "wire-span"
        ]

        let result = CoralogixRum.resolveHybridTraceContext(from: dict)

        XCTAssertEqual(result.traceId, "wire-trace")
        XCTAssertEqual(result.spanId, "wire-span")
    }

    /// Ids are resolved as a pair: a lone custom traceId (no matching span id) must not be used; the
    /// resolver drops to the next complete pair so the exported span never mixes ids from two sources.
    func testPartialCustomPairFallsBackToWirePair() {
        let dict: [String: Any] = [
            Keys.customTraceId.rawValue: "custom-trace",
            // customSpanId intentionally absent
            Keys.traceId.rawValue: "wire-trace",
            Keys.spanId.rawValue: "wire-span"
        ]

        let result = CoralogixRum.resolveHybridTraceContext(from: dict)

        XCTAssertEqual(result.traceId, "wire-trace")
        XCTAssertEqual(result.spanId, "wire-span")
    }

    /// No ids at all → empty pair, so `getTraceAndSpanId` falls back to the native OTel span id (unchanged behavior).
    func testReturnsEmptyPairWhenNoIdsProvided() {
        let result = CoralogixRum.resolveHybridTraceContext(from: [Keys.url.rawValue: "https://example.com"])

        XCTAssertEqual(result.traceId, "")
        XCTAssertEqual(result.spanId, "")
    }

    // MARK: - End-to-end: resolved ids reach the exporter via getTraceAndSpanId

    /// Guards the whole chain: reportHybridNetworkRequest sets customTraceId/customSpanId from the
    /// resolved pair, and the exporter reads them back via getTraceAndSpanId. A wire-id-only payload
    /// must surface the wire ids on the exported span — not a fresh, native auto-generated id that was never on the wire.
    func testWireIdsSurfaceOnExportedSpan() {
        let resolved = CoralogixRum.resolveHybridTraceContext(from: [
            Keys.traceId.rawValue: "wire-trace",
            Keys.spanId.rawValue: "wire-span"
        ])

        let span = MockSpanData(
            attributes: [
                Keys.customTraceId.rawValue: AttributeValue(resolved.traceId),
                Keys.customSpanId.rawValue: AttributeValue(resolved.spanId)
            ],
            startTime: Date(), endTime: Date(),
            spanId: "native-span", traceId: "native-trace",
            name: "HTTP GET", kind: 3
        )

        let result = Helper.getTraceAndSpanId(otel: span)

        XCTAssertEqual(result.traceId, "wire-trace",
                       "Exported span must carry the wire traceId, not the native auto-generated one")
        XCTAssertEqual(result.spanId, "wire-span")
    }
}
