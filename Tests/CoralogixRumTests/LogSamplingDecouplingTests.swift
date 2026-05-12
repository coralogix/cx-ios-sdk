//
//  LogSamplingDecouplingTests.swift
//
//  End-to-end coverage for the sampling-decoupling pipeline introduced in PIPEV2-3365
//  (T1: ExcludableInstrumentation; T2: per-session reroll + init-flow decoupling;
//   T3: per-span sampling filter in CoralogixExporter).
//
//  Routes real `SpanData` through `CoralogixExporter.export()` and captures what
//  survives the sampling filter via the `tracesExporter` callback (which fires after
//  the sampling/URL/error filters but before encode/upload). A `SamplingMockSpanUploader`
//  is wired in to keep tests offline. Shared helpers (`EventTypeCapture`, factories,
//  mock uploader) live in `SamplingTestHelpers.swift` and are reused by `HybridAPITests`.
//
//  "Deterministic sampler stub": SDKSampler.shouldInitialized() uses
//  Int.random(in: 0..<100) < sampleRate, which is deterministic at the boundaries
//  (0 always rolls false, 100 always rolls true). Every case below uses one of those.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class LogSamplingDecouplingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Static SDK state can leak between tests if a prior init was not torn down.
        CoralogixRum.isInitialized = false
    }

    // MARK: - Case 1: sampleRate=0, exclude=[] ⇒ SDK does not initialize

    func testCase1_sampleRateZero_excludeEmpty_doesNotInitialize() {
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 0, exclude: []))
        defer { rum.shutdown() }

        XCTAssertFalse(rum.isInitialized,
                       "Legacy contract: sampleRate=0 + excludeFromSampling=[] must NOT initialize.")
        XCTAssertNil(rum.coralogixExporter,
                     "Skipped init must not create an exporter.")
    }

    // MARK: - Case 2: sampleRate=0, exclude=[.logs] ⇒ logs export, others drop

    func testCase2_sampleRateZero_excludeLogs_logsExportOthersDrop() throws {
        let capture = EventTypeCapture()
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 0,
                                                            exclude: [.logs],
                                                            tracesExporter: capture.tracesExporterCallback()))
        defer { rum.shutdown() }

        let exporter = try requireExporter(rum)
        exporter.spanUploader = SamplingMockSpanUploader()

        _ = exporter.export(spans: [
            makeSamplingSpan(eventType: .log),
            makeSamplingSpan(eventType: .error),
            makeSamplingSpan(eventType: .networkRequest)
        ], explicitTimeout: nil)

        XCTAssertEqual(capture.eventTypes, ["log"],
                       "Sampled-out + exclude=[.logs] must let only log spans through; errors and network spans drop.")
    }

    // MARK: - Case 3: sampleRate=100, exclude=[.logs] ⇒ all spans export

    func testCase3_sampleRateHundred_excludeLogs_allSpansExport() throws {
        let capture = EventTypeCapture()
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100,
                                                            exclude: [.logs],
                                                            tracesExporter: capture.tracesExporterCallback()))
        defer { rum.shutdown() }

        let exporter = try requireExporter(rum)
        exporter.spanUploader = SamplingMockSpanUploader()

        _ = exporter.export(spans: [
            makeSamplingSpan(eventType: .log),
            makeSamplingSpan(eventType: .error),
            makeSamplingSpan(eventType: .networkRequest)
        ], explicitTimeout: nil)

        XCTAssertEqual(Set(capture.eventTypes),
                       Set(["log", "error", "network-request"]),
                       "Sampled-in: every span passes regardless of excludeFromSampling.")
    }

    // MARK: - Case 4: session rotation re-rolls sampling (and the reroll callback actually runs)

    func testCase4_sessionRotation_sampleRateZero_rerollFlipsBackToFalse() throws {
        // Rationale: with sampleRate=0 the deterministic outcome is `false`. Manually flip
        // the flag to `true`, rotate the session, and watch the reroll callback flip it
        // back. Asserting "the value didn't change" alone would also be true if the callback
        // never fired — the manual flip closes that gap.
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 0, exclude: [.logs]))
        defer { rum.shutdown() }

        let exporter = try requireExporter(rum)
        XCTAssertEqual(exporter.isCurrentSessionSampledIn(), false,
                       "Initial roll at sampleRate=0 must be sampled-out.")

        exporter.updateSessionSampling(sampledIn: true)
        XCTAssertEqual(exporter.isCurrentSessionSampledIn(), true,
                       "Manual flip should set the flag to true.")

        rum.sessionManager?.setupSessionMetadata()

        XCTAssertEqual(exporter.isCurrentSessionSampledIn(), false,
                       "Rotation must invoke the reroll callback; sampleRate=0 deterministically re-rolls to false.")
    }

    func testCase4_sessionRotation_sampleRateHundred_rerollFlipsBackToTrue() throws {
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        defer { rum.shutdown() }

        let exporter = try requireExporter(rum)
        XCTAssertEqual(exporter.isCurrentSessionSampledIn(), true,
                       "Initial roll at sampleRate=100 must be sampled-in.")

        exporter.updateSessionSampling(sampledIn: false)
        XCTAssertEqual(exporter.isCurrentSessionSampledIn(), false,
                       "Manual flip should set the flag to false.")

        rum.sessionManager?.setupSessionMetadata()

        XCTAssertEqual(exporter.isCurrentSessionSampledIn(), true,
                       "Rotation must invoke the reroll callback; sampleRate=100 deterministically re-rolls to true.")
    }

    // MARK: - Case 5: multiple categories ⇒ only those pass

    func testCase5_sampleRateZero_excludeLogsAndErrors_onlyThoseTwoPass() throws {
        let capture = EventTypeCapture()
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 0,
                                                            exclude: [.logs, .errors],
                                                            tracesExporter: capture.tracesExporterCallback()))
        defer { rum.shutdown() }

        let exporter = try requireExporter(rum)
        exporter.spanUploader = SamplingMockSpanUploader()

        _ = exporter.export(spans: [
            makeSamplingSpan(eventType: .log),
            makeSamplingSpan(eventType: .error),
            makeSamplingSpan(eventType: .networkRequest),
            makeSamplingSpan(eventType: .mobileVitals)
        ], explicitTimeout: nil)

        XCTAssertEqual(Set(capture.eventTypes), Set(["log", "error"]),
                       "Sampled-out + exclude=[.logs, .errors] must let exactly those two categories through.")
    }

    // MARK: - Case 6: thread-safety smoke — rotate on one queue while exporting on another

    func testCase6_sessionRotation_concurrentWithExport_threadSafetySmoke() throws {
        let capture = EventTypeCapture()
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 0,
                                                            exclude: [.logs],
                                                            tracesExporter: capture.tracesExporterCallback()))
        defer { rum.shutdown() }

        let exporter = try requireExporter(rum)
        exporter.spanUploader = SamplingMockSpanUploader()

        let iterations = 100
        let group = DispatchGroup()

        // Rotation queue: forces a reroll repeatedly.
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<iterations {
                rum.sessionManager?.setupSessionMetadata()
            }
            group.leave()
        }

        // Export queue: pushes 1 log span (excluded ⇒ should always pass) per iteration.
        // Span is built once and reused; export() dedups by spanId *within a single call*,
        // not across calls, so the duplicate spanId here is harmless.
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let span = makeSamplingSpan(eventType: .log)
            for _ in 0..<iterations {
                _ = exporter.export(spans: [span], explicitTimeout: nil)
            }
            group.leave()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success,
                       "Concurrent rotate+export must complete within 10s without deadlock.")

        XCTAssertEqual(exporter.isCurrentSessionSampledIn(), false,
                       "Final roll at sampleRate=0 must remain sampled-out after every reroll.")
        // Count only `"log"` entries: other spans the SDK might emit as a side effect of init or
        // session rotation would be filtered out by sampleRate=0 + exclude=[.logs] anyway, but
        // counting them here would flake the assertion if any happened to carry event_type=log.
        let logCount = capture.eventTypes.filter { $0 == "log" }.count
        XCTAssertEqual(logCount, iterations,
                       "Every log export must survive the filter (logs are in excludeFromSampling).")
        let nonLog = Set(capture.eventTypes).subtracting(["log"])
        XCTAssertTrue(nonLog.isEmpty,
                      "No non-log event_types should pass the filter; saw: \(nonLog.sorted())")
    }

    // MARK: - Helpers

    private func requireExporter(_ rum: CoralogixRum) throws -> CoralogixExporter {
        return try XCTUnwrap(rum.coralogixExporter, "Exporter must exist after init.")
    }
}
