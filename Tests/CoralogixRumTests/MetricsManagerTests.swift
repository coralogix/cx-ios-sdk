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
        // Remove the subscriber unconditionally so a failed assertion in any test
        // that calls addMetricKitObservers() cannot pollute subsequent test runs.
        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
        // Stops a started ANR watchdog, which would otherwise watch the main thread for later tests.
        metricsManager.removeObservers()
        mockFPSMonitor = nil
        super.tearDown()
    }
    
    func testStartANRMonitoring() {
        metricsManager.startANRMonitoring()
        XCTAssertEqual(metricsManager.anrDetector?.isMonitoring, true)
    }

    func testStartANRMonitoring_twice_keepsOneDetector() throws {
        metricsManager.startANRMonitoring()
        let first = try XCTUnwrap(metricsManager.anrDetector)

        metricsManager.startANRMonitoring()

        XCTAssertTrue(metricsManager.anrDetector === first)
        metricsManager.removeObservers()
        XCTAssertFalse(first.isMonitoring)
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
        XCTAssertEqual(receivedEvent?.errorMessage, "Application Not Responding for at least 1000 ms.")
        XCTAssertTrue(vitalsCollector.batches.isEmpty, "metricsCollector must not be called for ANR events")
    }

}

// MARK: - Test Helpers

// Mock class to simulate the behavior of fpsDetector
class MockFPSTrigger: FPSDetector {
    var stopMonitoringCalled = false
    
    override func stopMonitoring() {
        stopMonitoringCalled = true
    }
}
