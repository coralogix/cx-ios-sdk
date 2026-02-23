//
//  ColdDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 16/09/2025.
//

import XCTest
import Foundation
import UIKit

@testable import Coralogix

class ColdDetectorTests: XCTestCase {
    var sut: ColdDetector!

    override func setUp() {
        super.setUp()
        sut = ColdDetector()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - processStartTime()

    /// Verifies that `processStartTime()` successfully reads the kernel process birth time via sysctl.
    /// The returned value must be in the past (before now) and positive, proving it reflects a real
    /// process start rather than a fallback or zero.
    func testProcessStartTime_returnsValidPastTime() throws {
        guard let startTime = ColdDetector.processStartTime() else {
            throw XCTSkip("sysctl unavailable in this sandbox environment")
        }

        let now = CFAbsoluteTimeGetCurrent()
        XCTAssertLessThan(startTime, now, "Process start time must be in the past")
        XCTAssertGreaterThan(startTime, 0, "Process start time must be a positive CFAbsoluteTime")
    }

    /// Verifies that `processStartTime()` returns a time earlier than `CFAbsoluteTimeGetCurrent()`
    /// recorded at SDK init — confirming we capture pre-main work that was previously missed.
    func testProcessStartTime_isEarlierThanSdkInit() throws {
        let sdkInitTime = CFAbsoluteTimeGetCurrent()

        guard let kernelStartTime = ColdDetector.processStartTime() else {
            throw XCTSkip("sysctl unavailable in this sandbox environment")
        }

        XCTAssertLessThan(kernelStartTime, sdkInitTime,
                          "Kernel process start must predate SDK init — it captures pre-main work")
    }

    // MARK: - startMonitoring()

    /// Verifies that `startMonitoring()` sets `launchStartTime` to the kernel process birth time,
    /// which should be earlier than any time recorded after the call.
    func testStartMonitoring_setsLaunchStartTime() throws {
        XCTAssertNil(sut.launchStartTime)

        sut.startMonitoring()

        let startTime = try XCTUnwrap(sut.launchStartTime, "startMonitoring() must set launchStartTime")
        XCTAssertLessThan(startTime, CFAbsoluteTimeGetCurrent(),
                          "launchStartTime should be in the past (kernel process birth or SDK init)")
    }

    // MARK: - Cold Start Measurement

    /// End-to-end test: verifies that posting `didBecomeActiveNotification` after `startMonitoring()`
    /// fires `handleColdClosure` with the correct dictionary structure and a positive duration.
    func testDidBecomeActive_afterStartMonitoring_reportsColdStart() {
        sut.startMonitoring()

        var receivedMetric: [String: Any]?
        sut.handleColdClosure = { receivedMetric = $0 }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertNotNil(receivedMetric, "handleColdClosure should be called on didBecomeActive")

        let inner = receivedMetric?[MobileVitalsType.cold.stringValue] as? [String: Any]
        XCTAssertNotNil(inner, "Payload must contain the cold key")
        XCTAssertEqual(inner?[Keys.mobileVitalsUnits.rawValue] as? String,
                       MeasurementUnits.milliseconds.stringValue,
                       "Units must be milliseconds")

        let duration = inner?[Keys.value.rawValue] as? Double
        XCTAssertNotNil(duration)
        XCTAssertGreaterThanOrEqual(duration ?? -1, 0, "Duration must be non-negative")
    }

    /// Verifies that cold start is reported exactly once even if `didBecomeActiveNotification`
    /// fires multiple times (e.g. app goes to background and returns after cold start).
    /// The observer is removed on first delivery so subsequent fires are ignored.
    func testDidBecomeActive_firesOnlyOnce() {
        sut.startMonitoring()

        var callCount = 0
        sut.handleColdClosure = { _ in callCount += 1 }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(callCount, 1, "Cold start must be reported exactly once")
    }

    /// Verifies that if `startMonitoring()` is never called, posting `didBecomeActiveNotification`
    /// does nothing — no observer is registered and no closure fires.
    func testDidBecomeActive_withoutStartMonitoring_doesNotReport() {
        var called = false
        sut.handleColdClosure = { _ in called = true }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertFalse(called, "handleColdClosure must not fire if startMonitoring() was never called")
    }

    /// Verifies that if `launchStartTime` is nil when `didBecomeActive` fires, no metric is reported
    /// and the observer is still removed (no leak into subsequent foreground cycles).
    func testDidBecomeActive_whenStartTimeNil_doesNotReport() {
        sut.startMonitoring()
        sut.launchStartTime = nil

        var called = false
        sut.handleColdClosure = { _ in called = true }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(called, "handleColdClosure must not fire when launchStartTime is nil")

        // A second post must also be ignored — confirms the observer was removed even on early return.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(called, "Observer must be removed even when guard exits early")
    }

    /// Verifies that `launchEndTime` is set to a non-nil value after `didBecomeActive` fires,
    /// acting as a latch to prevent duplicate reports.
    func testDidBecomeActive_setsLaunchEndTime() {
        sut.startMonitoring()
        XCTAssertNil(sut.launchEndTime)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertNotNil(sut.launchEndTime, "launchEndTime must be set after cold start is reported")
    }

    // MARK: - calculateTime()

    /// Verifies the helper returns the correct positive delta and clamps negative values to zero.
    func testCalculateTime_isNonNegative() {
        XCTAssertEqual(sut.calculateTime(start: 10, stop: 25), 15, accuracy: 0.000_1)
        XCTAssertEqual(sut.calculateTime(start: 25, stop: 10), 0, accuracy: 0.000_1, "Negative delta must clamp to zero")
        XCTAssertEqual(sut.calculateTime(start: 42, stop: 42), 0, accuracy: 0.000_1, "Zero delta must return zero")
    }

    // MARK: - Deallocation

    /// Verifies that `deinit` removes all observers so that a deallocated `ColdDetector`
    /// never processes `didBecomeActiveNotification`, preventing crashes or stale callbacks.
    /// Explicitly asserts deallocation via a weak reference before posting notifications.
    func testDeinit_removesObservers() {
        var closureCalled = false
        weak var weakRef: ColdDetector?

        func createAndRelease() {
            let local = ColdDetector()
            weakRef = local
            local.startMonitoring()
            local.handleColdClosure = { _ in closureCalled = true }
            // `local` goes out of scope — deinit is called synchronously.
        }

        createAndRelease()

        XCTAssertNil(weakRef, "ColdDetector must have deallocated before notifications are posted")

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertFalse(closureCalled, "No closure should fire after ColdDetector is deallocated")
    }
}
