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
        mockFPSMonitor = nil
        super.tearDown()
    }
    
    func testStartANRMonitoring() {
        metricsManager.startANRMonitoring()
        XCTAssertNotNil(metricsManager.anrDetector, "ANR monitoring should start and anrDetector should be initialized")
    }
    
    func testANRErrorClosureIsCalled() {
        let expectation = XCTestExpectation(description: "ANR error closure should be called")
        var receivedErrorMessage: String?
        var receivedErrorType: String?
        var mobileVitalsWasCalled = false
        
        // Set up mobile vitals closure (should NOT be called)
        metricsManager.metricsManagerClosure = { _ in
            mobileVitalsWasCalled = true
        }
        
        // Set up the ANR error closure
        metricsManager.anrErrorClosure = { errorMessage, errorType in
            receivedErrorMessage = errorMessage
            receivedErrorType = errorType
            expectation.fulfill()
        }
        
        // Start monitoring
        metricsManager.startANRMonitoring()
        
        // Simulate ANR detection by directly calling the detector's handleANR
        metricsManager.anrDetector?.handleANR()
        
        wait(for: [expectation], timeout: 1.0)
        
        // Verify the error message and type
        XCTAssertNotNil(receivedErrorMessage, "Error message should be received")
        XCTAssertNotNil(receivedErrorType, "Error type should be received")
        XCTAssertEqual(receivedErrorType, "ANR", "Error type should be 'ANR'")
        XCTAssertEqual(receivedErrorMessage, "Application Not Responding", "Error message should be 'Application Not Responding'")
        
        // Verify mobile vitals closure was NOT called
        XCTAssertFalse(mobileVitalsWasCalled, "Mobile vitals closure should not be called for ANR events")
    }
    
    func testANRDoesNotCallMobileVitalsClosure() {
        let expectation = XCTestExpectation(description: "Mobile vitals closure should NOT be called for ANR")
        expectation.isInverted = true
        
        // Set up the mobile vitals closure (should NOT be called)
        metricsManager.metricsManagerClosure = { _ in
            XCTFail("Mobile vitals closure should not be called for ANR events")
            expectation.fulfill()
        }
        
        // Set up the ANR error closure (should be called)
        metricsManager.anrErrorClosure = { _, _ in
            // ANR error closure called correctly
        }
        
        // Start monitoring
        metricsManager.startANRMonitoring()
        
        // Simulate ANR detection
        metricsManager.anrDetector?.handleANR()
        
        wait(for: [expectation], timeout: 1.0)
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
    /// hang is forwarded to `anrErrorClosure` — not to `metricsManagerClosure` (mobile vitals).
    func testAddMetricKitObservers_hangRoutesToAnrErrorClosure() {
        var errorMessage: String?
        var errorType: String?
        var mobileVitalsCalled = false

        metricsManager.metricsManagerClosure = { _ in mobileVitalsCalled = true }
        metricsManager.anrErrorClosure = { msg, type in
            errorMessage = msg
            errorType = type
        }

        metricsManager.addMetricKitObservers()

        MyMetricSubscriber.shared.processHang(MockHangDiagnostic(hangDurationMs: 3000))

        XCTAssertEqual(errorType, "MXHangDiagnostic", "Hang must be routed to the error closure")
        XCTAssertEqual(errorMessage, "App hang detected by MetricKit for 3000 ms")
        XCTAssertFalse(mobileVitalsCalled, "Hang must not trigger mobile vitals closure")

        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
    }

    /// Verifies that when `anrErrorClosure` is not set, a MetricKit hang is silently dropped
    /// without crashing.
    func testAddMetricKitObservers_hangDroppedWhenAnrErrorClosureIsNil() {
        metricsManager.anrErrorClosure = nil
        metricsManager.addMetricKitObservers()

        MyMetricSubscriber.shared.processHang(MockHangDiagnostic(hangDurationMs: 1500))
        // Passes if no crash occurs

        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
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
