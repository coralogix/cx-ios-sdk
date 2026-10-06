//
//  MetricsManagerTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 11/09/2024.
//

import XCTest
import MetricKit
import CoralogixInternal
@testable import Coralogix

final class MetricsManagerTests: XCTestCase {
    
    var metricsManager: MetricsManager!
    var mockFPSMonitor: MockFPSTrigger!

    override func setUp() {
        super.setUp()
        self.metricsManager = MetricsManager()
        self.mockFPSMonitor = MockFPSTrigger()
    }

    override func tearDown() {
        // Reset shared singleton state so a mid-test failure never leaks
        // hangDiagnosticClosure into subsequent tests.
        MyMetricSubscriber.shared.hangDiagnosticClosure = nil
        // Remove the subscriber unconditionally so a failed assertion in any test
        // that calls addMetricKitObservers() cannot pollute subsequent test runs.
        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
        mockFPSMonitor = nil
        super.tearDown()
    }
    
    func testStartANRMonitoring() {
        metricsManager.startANRMonitoring()
        XCTAssertNotNil(metricsManager.anrDetector, "ANR monitoring should start and anrDetector should be initialized")
    }
    
    // MARK: - Cold start wiring

    /// A late init's recorded launch reaches the collector even when the collector is wired after
    /// cold monitoring starts in the same main-queue turn — SDK init order must not decide whether
    /// the launch is reported, because the process-wide claim makes a dropped report final.
    func testStartColdStartMonitoring_recordedLaunchReachesCollectorWiredAfterStart() throws {
        let processStart = try XCTUnwrap(ColdDetector.processStartTime(), "sysctl unavailable")
        let launch = FakeLaunchRecording()
        launch.firstActivation = processStart + 0.5
        metricsManager.launchRecording = launch

        metricsManager.startColdStartMonitoring()
        let collector = BatchRecordingCollector()
        metricsManager.metricsCollector = collector

        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)

        let cold = try XCTUnwrap(collector.batches.flatMap { $0 }.first { $0.name == MobileVitalsType.cold.stringValue })
        let payload = try XCTUnwrap(cold.payload as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(payload[Keys.value.rawValue] as? Double), 500, accuracy: 1)
        XCTAssertEqual(launch.claimCount, 1)
    }

    /// Shutdown tears down the cold and warm detectors like every other detector, so a re-init
    /// starts them fresh instead of being skipped by their `== nil` start guards.
    func testRemoveObservers_stopsColdAndWarmDetectors() {
        metricsManager.launchRecording = FakeLaunchRecording()
        metricsManager.startColdStartMonitoring()
        metricsManager.startWarmStartMonitoring()
        XCTAssertNotNil(metricsManager.coldDetector)
        XCTAssertNotNil(metricsManager.warmDetector)

        metricsManager.removeObservers()

        XCTAssertNil(metricsManager.coldDetector)
        XCTAssertNil(metricsManager.warmDetector)
    }

    func testANRErrorIsRoutedToEventReporter() {
        let expectation = XCTestExpectation(description: "ANRErrorEvent should be reported")
        var receivedEvent: ANRErrorEvent?
        let vitalsCollector = BatchRecordingCollector()

        // metricsCollector must NOT receive anything for an ANR event
        metricsManager.metricsCollector = vitalsCollector

        // ANR routes through the EventReporter protocol
        metricsManager.eventReporter = RecordingEventReporter { event in
            receivedEvent = event as? ANRErrorEvent
            expectation.fulfill()
        }

        metricsManager.startANRMonitoring()
        metricsManager.anrDetector?.handleANR()

        wait(for: [expectation], timeout: 1.0)

        // Wire-constant guard: hard-coded strings catch accidental WireValues changes
        XCTAssertEqual(receivedEvent?.errorType, "ANR", "Error type should be 'ANR'")
        XCTAssertEqual(receivedEvent?.errorMessage, "Application Not Responding", "Error message should be 'Application Not Responding'")
        XCTAssertTrue(vitalsCollector.batches.isEmpty, "metricsCollector must not be called for ANR events")
    }

    // MARK: - MetricKit Hang Diagnostics

    /// Verifies that `processHang` fires `hangDiagnosticClosure` with the correct error type
    /// so hang events are routed to the error pipeline and not to mobile vitals.
    func testProcessHang_firesHangDiagnosticClosure() {
        var receivedMessage: String?
        var receivedErrorType: String?

        MyMetricSubscriber.shared.hangDiagnosticClosure = { message, errorType in
            receivedMessage = message
            receivedErrorType = errorType
        }

        MyMetricSubscriber.shared.processHang(MockHangDiagnostic(hangDurationMs: 2500))

        XCTAssertEqual(receivedErrorType, "MXHangDiagnostic",
                       "Error type must be MXHangDiagnostic so it is distinguishable from runtime ANR")
        XCTAssertEqual(receivedMessage, "App hang detected by MetricKit for 2500 ms",
                       "Message must include the exact duration in whole milliseconds")
    }

    /// Verifies that the duration from `HangDiagnosticProviding` is rounded to whole
    /// milliseconds in the error message, preventing floating-point noise.
    func testProcessHang_durationIsRoundedToWholeMs() {
        var receivedMessage: String?

        MyMetricSubscriber.shared.hangDiagnosticClosure = { message, _ in
            receivedMessage = message
        }

        MyMetricSubscriber.shared.processHang(MockHangDiagnostic(hangDurationMs: 1234.987))

        XCTAssertEqual(receivedMessage, "App hang detected by MetricKit for 1235 ms",
                       "Duration should be rounded to the nearest whole millisecond")
    }

    /// Verifies that when `hangDiagnosticClosure` is nil, `processHang` is a no-op
    /// and does not crash.
    func testProcessHang_whenClosureIsNil_doesNotCrash() {
        MyMetricSubscriber.shared.hangDiagnosticClosure = nil
        MyMetricSubscriber.shared.processHang(MockHangDiagnostic(hangDurationMs: 1000))
        // Passes if no crash occurs
    }

    /// Verifies that `addMetricKitObservers()` wires `hangDiagnosticClosure` so that a MetricKit
    /// hang is forwarded to `eventReporter` as an `ANRErrorEvent` — not to `metricsCollector` (mobile vitals).
    func testAddMetricKitObservers_hangRoutesToEventReporter() {
        var receivedEvent: ANRErrorEvent?
        let vitalsCollector = BatchRecordingCollector()

        metricsManager.metricsCollector = vitalsCollector
        metricsManager.eventReporter = RecordingEventReporter { event in
            receivedEvent = event as? ANRErrorEvent
        }

        metricsManager.addMetricKitObservers()

        MyMetricSubscriber.shared.processHang(MockHangDiagnostic(hangDurationMs: 3000))

        XCTAssertEqual(receivedEvent?.errorType, "MXHangDiagnostic", "Hang must be routed via EventReporter as ANRErrorEvent")
        XCTAssertEqual(receivedEvent?.errorMessage, "App hang detected by MetricKit for 3000 ms")
        XCTAssertTrue(vitalsCollector.batches.isEmpty, "Hang must not trigger metricsCollector")
    }

    /// Verifies that when `eventReporter` is not set, a MetricKit hang is silently dropped
    /// without crashing.
    func testAddMetricKitObservers_hangDroppedWhenEventReporterIsNil() {
        // eventReporter is nil by default — explicit no-op.
        metricsManager.addMetricKitObservers()

        MyMetricSubscriber.shared.processHang(MockHangDiagnostic(hangDurationMs: 1500))
        // Passes if no crash occurs
    }
}

// MARK: - Test Helpers

/// Mock that stands in for `MXHangDiagnostic` in tests.
/// `MXHangDiagnostic` has no public initializer, so we use the
/// `HangDiagnosticProviding` protocol to inject test values.
struct MockHangDiagnostic: HangDiagnosticProviding {
    let hangDurationMs: Double
}

// Mock class to simulate the behavior of fpsDetector
class MockFPSTrigger: FPSDetector {
    var stopMonitoringCalled = false
    
    override func stopMonitoring() {
        stopMonitoringCalled = true
    }
}
