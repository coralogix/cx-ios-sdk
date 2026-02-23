//
//  WarmDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 18/09/2025.
//

import XCTest
import Foundation
import UIKit

@testable import Coralogix

class WarmDetectorTests: XCTestCase {
    var sut: WarmDetector!

    override func setUp() {
        super.setUp()
        sut = WarmDetector()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Warm Start Measurement

    /// Verifies that when `foregroundStartTime` is already set (app came from background),
    /// `appDidBecomeActiveNotification` fires `handleWarmClosure` with the correct dictionary
    /// structure: a `warm` key containing `units` (milliseconds) and a positive `value`.
    func testWarmStart_whenForegroundStartTimeSet_callsClosureWithCorrectStructure() {
        sut.foregroundStartTime = CFAbsoluteTimeGetCurrent() - 1.0

        var receivedMetric: [String: Any]?
        sut.handleWarmClosure = { receivedMetric = $0 }

        sut.appDidBecomeActiveNotification()

        XCTAssertNotNil(receivedMetric, "handleWarmClosure should be called when foregroundStartTime is set")

        let inner = receivedMetric?[MobileVitalsType.warm.stringValue] as? [String: Any]
        XCTAssertNotNil(inner, "Payload must contain warm key")
        XCTAssertEqual(inner?[Keys.mobileVitalsUnits.rawValue] as? String,
                       MeasurementUnits.milliseconds.stringValue,
                       "Units must be milliseconds")

        let duration = inner?[Keys.value.rawValue] as? Double
        XCTAssertNotNil(duration)
        XCTAssertGreaterThan(duration ?? 0, 0, "Duration must be positive")
    }

    /// Verifies that if the app becomes active without a prior background event
    /// (e.g. cold start / first launch), `handleWarmClosure` is never called because
    /// `foregroundStartTime` is nil and there is nothing to measure.
    func testWarmStart_whenNoForegroundStartTime_doesNotCallClosure() {
        sut.foregroundStartTime = nil

        var called = false
        sut.handleWarmClosure = { _ in called = true }

        sut.appDidBecomeActiveNotification()

        XCTAssertFalse(called, "handleWarmClosure must not be called when foregroundStartTime is nil")
    }

    /// Verifies that calling `appDidBecomeActiveNotification` a second time within the same
    /// foreground cycle does not report a second warm start event. Once `foregroundEndTime`
    /// is set, the guard prevents a duplicate report.
    func testWarmStart_isNotReportedTwice_forSameForegroundCycle() {
        sut.foregroundStartTime = CFAbsoluteTimeGetCurrent() - 0.5

        var callCount = 0
        sut.handleWarmClosure = { _ in callCount += 1 }

        sut.appDidBecomeActiveNotification()
        sut.appDidBecomeActiveNotification()

        XCTAssertEqual(callCount, 1, "Warm start should only be reported once per foreground cycle")
    }

    // MARK: - Background / Foreground Lifecycle

    /// Verifies that entering the background sets `warmMetricIsActive` to `true`,
    /// which arms the detector so it knows the next foreground transition is a warm start.
    func testBackground_armsDetector() {
        XCTAssertFalse(sut.warmMetricIsActive)

        sut.appDidEnterBackgroundNotification()

        XCTAssertTrue(sut.warmMetricIsActive, "warmMetricIsActive should be true after entering background")
    }

    /// Verifies that when the detector is armed (`warmMetricIsActive == true`),
    /// `appWillEnterForegroundNotification` records `foregroundStartTime` and resets
    /// `warmMetricIsActive` to prevent double-arming on subsequent transitions.
    func testWillEnterForeground_whenArmed_recordsStartTime() {
        sut.warmMetricIsActive = true
        sut.foregroundStartTime = nil

        sut.appWillEnterForegroundNotification()

        XCTAssertNotNil(sut.foregroundStartTime, "foregroundStartTime should be recorded when armed")
        XCTAssertFalse(sut.warmMetricIsActive, "warmMetricIsActive should be reset after recording start time")
    }

    /// Verifies that if `willEnterForeground` fires while the detector is NOT armed
    /// (e.g. the app was never backgrounded), `foregroundStartTime` is not recorded,
    /// ensuring no phantom warm start is emitted.
    func testWillEnterForeground_whenNotArmed_doesNotRecordStartTime() {
        sut.warmMetricIsActive = false
        sut.foregroundStartTime = nil

        sut.appWillEnterForegroundNotification()

        XCTAssertNil(sut.foregroundStartTime, "foregroundStartTime should not be set if detector was not armed")
    }

    /// End-to-end test using real `NotificationCenter` posts to simulate a full app lifecycle:
    /// background → foreground. Verifies the complete flow from notification receipt to metric
    /// reporting, including the correct dictionary structure and units.
    func testFullCycle_backgroundThenForeground_reportsWarmStart() {
        var receivedMetric: [String: Any]?
        sut.handleWarmClosure = { receivedMetric = $0 }

        sut.startMonitoring()

        // Simulate going to background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        // Simulate returning to foreground
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertNotNil(receivedMetric, "Warm start should be reported after a full background → foreground cycle")

        let inner = receivedMetric?[MobileVitalsType.warm.stringValue] as? [String: Any]
        XCTAssertEqual(inner?[Keys.mobileVitalsUnits.rawValue] as? String,
                       MeasurementUnits.milliseconds.stringValue)
        XCTAssertNotNil(inner?[Keys.value.rawValue] as? Double)
    }

    /// Verifies that the detector correctly resets after each foreground cycle,
    /// allowing it to report warm start for 3 consecutive background → foreground
    /// transitions without missing or duplicating any event.
    func testMultipleCycles_eachCycleReportsWarmStart() {
        var callCount = 0
        sut.handleWarmClosure = { _ in callCount += 1 }

        sut.startMonitoring()

        for _ in 1...3 {
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }

        XCTAssertEqual(callCount, 3, "Warm start should be reported for every background → foreground cycle")
    }

    /// Verifies that firing `willEnterForeground` and `didBecomeActive` without a preceding
    /// `didEnterBackground` (cold start scenario) does not produce a warm start event,
    /// since the detector was never armed by a background transition.
    func testNoBackground_noWarmStart() {
        var callCount = 0
        sut.handleWarmClosure = { _ in callCount += 1 }

        sut.startMonitoring()

        // Fire foreground notifications WITHOUT ever going to background first
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(callCount, 0, "Warm start should not fire if app never went to background")
    }

    // MARK: - All Platforms Receive Notifications (CX-31661)

    /// Verifies that WarmDetector registers UIApplication observers unconditionally,
    /// ensuring warm start is reported for native Swift, Flutter, and React Native apps.
    func testStartMonitoring_registersAllObserversForAllPlatforms() {
        // Verify a full background → foreground cycle is captured without any
        // platform-specific configuration. UIApplication notifications fire for
        // all iOS apps regardless of framework.
        var receivedMetric: [String: Any]?
        sut.handleWarmClosure = { receivedMetric = $0 }

        sut.startMonitoring()

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertNotNil(receivedMetric,
                        "Warm start must be reported on all platforms (Swift, Flutter, React Native) - CX-31661")
    }

    // MARK: - Deallocation

    /// Verifies that `deinit` removes all `NotificationCenter` observers so that
    /// a deallocated `WarmDetector` never processes lifecycle notifications,
    /// preventing use-after-free crashes or stale closure calls.
    func testDeinit_removesObservers() {
        var closureCalled = false

        // Use a helper to guarantee the detector is deallocated before we post
        // notifications. Moving allocation/deallocation into a separate function
        // ensures ARC releases the object before the caller resumes.
        func createAndRelease() {
            let local = WarmDetector()
            local.startMonitoring()
            local.handleWarmClosure = { _ in closureCalled = true }
            // `local` goes out of scope here — deinit is called synchronously.
        }

        createAndRelease()

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertFalse(closureCalled, "No closure should fire after WarmDetector is deallocated")
    }
}
