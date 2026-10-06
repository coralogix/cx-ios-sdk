//
//  ColdDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 16/09/2025.
//

import XCTest
import Foundation
import UIKit
#if canImport(CoralogixBootstrap)
import CoralogixBootstrap
#endif

@testable import Coralogix

class ColdDetectorTests: XCTestCase {
    var sut: ColdDetector!
    var launch: FakeLaunchRecording!

    override func setUp() {
        super.setUp()
        // Defaults to the native-init path: no activation recorded yet, claim available.
        launch = FakeLaunchRecording()
        sut = ColdDetector(launchRecording: launch)
    }

    override func tearDown() {
        sut = nil
        launch = nil
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
        // Pin a recent start so the duration is deterministic and under the cap regardless
        // of how long the test process has been alive (kernel birth time could exceed it).
        sut.launchStartTime = CFAbsoluteTimeGetCurrent() - 1

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
        // Pin a recent start so the (single) report isn't dropped by the cap.
        sut.launchStartTime = CFAbsoluteTimeGetCurrent() - 1

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

    // MARK: - Prewarm / background-launch filtering

    /// Verifies that a prewarmed launch (iOS spawns the process in the background ahead of
    /// user intent) is dropped — the kernel-birth → didBecomeActive delta is not a real cold
    /// start and would otherwise report multi-hour durations.
    func testDidBecomeActive_whenPrewarmed_doesNotReport() {
        sut.startMonitoring()
        sut.isPrewarmedLaunch = { true }

        var called = false
        sut.handleColdClosure = { _ in called = true }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertFalse(called, "Prewarmed launch must not emit a cold-start metric")
    }

    /// Verifies a non-prewarmed launch still reports normally — proves the prewarm guard
    /// doesn't suppress legitimate cold starts.
    func testDidBecomeActive_whenNotPrewarmed_reports() {
        sut.startMonitoring()
        sut.isPrewarmedLaunch = { false }
        // Pin a recent start so the cap can't drop the report — isolates the prewarm path.
        sut.launchStartTime = CFAbsoluteTimeGetCurrent() - 1

        var called = false
        sut.handleColdClosure = { _ in called = true }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertTrue(called, "A normal (non-prewarmed) launch must emit a cold-start metric")
    }

    /// Verifies a launch whose duration exceeds the sane ceiling (background launch skew) is
    /// dropped. `launchStartTime` is set far enough in the past to push the delta over the cap.
    func testDidBecomeActive_whenDurationExceedsCap_doesNotReport() {
        sut.startMonitoring()
        // Start time well beyond the 60s cap (cap is ms; CFAbsoluteTime is seconds).
        let secondsOverCap = (ColdDetector.maxReasonableColdStartMs / 1000) + 60
        sut.launchStartTime = CFAbsoluteTimeGetCurrent() - secondsOverCap

        var called = false
        sut.handleColdClosure = { _ in called = true }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertFalse(called, "Cold-start durations beyond the cap must be dropped")
    }

    /// Verifies a launch just under the cap still reports — proves the cap doesn't drop
    /// legitimate (if slow) cold starts.
    func testDidBecomeActive_whenDurationUnderCap_reports() {
        sut.startMonitoring()
        // 1s ago → ~1000ms, comfortably under the cap.
        sut.launchStartTime = CFAbsoluteTimeGetCurrent() - 1

        var receivedDuration: Double?
        sut.handleColdClosure = { dict in
            let inner = dict[MobileVitalsType.cold.stringValue] as? [String: Any]
            receivedDuration = inner?[Keys.value.rawValue] as? Double
        }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let duration = try? XCTUnwrap(receivedDuration)
        XCTAssertNotNil(duration, "A sub-cap launch must emit a cold-start metric")
        XCTAssertLessThanOrEqual(duration ?? .greatestFiniteMagnitude,
                                 ColdDetector.maxReasonableColdStartMs,
                                 "Reported duration must be within the cap")
    }

    // MARK: - Recorder hand-off (late init)

    /// Runs the main-queue turn `startMonitoring()` defers the recorded-activation report to.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    /// Captures each reported cold duration.
    private func recordColdDurations() -> () -> [Double] {
        var durations: [Double] = []
        sut.handleColdClosure = { dict in
            let inner = dict[MobileVitalsType.cold.stringValue] as? [String: Any]
            if let value = inner?[Keys.value.rawValue] as? Double { durations.append(value) }
        }
        return { durations }
    }

    /// Late init (React Native / Flutter): the first activation already happened, so the cold
    /// start is reported on the next main-queue turn and measures process birth → that activation.
    /// A later activation must not produce a second cold — that was the re-activation bug.
    func testStartMonitoring_whenFirstActivationRecorded_reportsAndIgnoresLaterActivations() throws {
        let processStart = try XCTUnwrap(ColdDetector.processStartTime(), "sysctl unavailable")
        launch.firstActivation = processStart + 0.5
        let durations = recordColdDurations()

        sut.startMonitoring()
        drainMainQueue()
        XCTAssertEqual(durations(), [500], "Cold start must be reported once, from the recorded activation")

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(durations().count, 1, "A later activation must never be reported as cold")
    }

    /// The report is deferred out of SDK init, so it never runs before the code that called
    /// `startMonitoring()` has finished wiring the metrics pipeline.
    func testStartMonitoring_whenFirstActivationRecorded_doesNotReportInsideTheCall() throws {
        let processStart = try XCTUnwrap(ColdDetector.processStartTime(), "sysctl unavailable")
        launch.firstActivation = processStart + 0.5
        let durations = recordColdDurations()

        sut.startMonitoring()
        XCTAssertTrue(durations().isEmpty)
        drainMainQueue()
        XCTAssertEqual(durations().count, 1)
    }

    /// Init raced the first activation: nothing was recorded at `startMonitoring()`, but by the
    /// time our observer fires the recorder has the first activation. The measurement must end at
    /// the recorded stamp, not at this delivery.
    func testDidBecomeActive_prefersRecordedActivationOverDeliveryTime() throws {
        sut.startMonitoring()
        drainMainQueue()
        let start = try XCTUnwrap(sut.launchStartTime)
        launch.firstActivation = start + 0.25
        let durations = recordColdDurations()

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(try XCTUnwrap(durations().first), 250, accuracy: 1)
    }

    /// A recorded activation more than the cap after process birth is a background start the task
    /// role missed, and is dropped on the late path as on the native one.
    func testStartMonitoring_whenRecordedActivationExceedsCap_doesNotReport() throws {
        let processStart = try XCTUnwrap(ColdDetector.processStartTime(), "sysctl unavailable")
        launch.firstActivation = processStart + (ColdDetector.maxReasonableColdStartMs / 1000) + 1
        let durations = recordColdDurations()

        sut.startMonitoring()
        drainMainQueue()

        XCTAssertTrue(durations().isEmpty)
        XCTAssertEqual(launch.claimCount, 0, "A dropped launch must not spend the process-wide claim")
    }

    /// The user left during the launch: process birth → first activation includes the time away.
    func testStartMonitoring_whenLaunchInterrupted_doesNotReport() throws {
        let processStart = try XCTUnwrap(ColdDetector.processStartTime(), "sysctl unavailable")
        launch.firstActivation = processStart + 20
        launch.launchWasInterrupted = true
        let durations = recordColdDurations()

        sut.startMonitoring()
        drainMainQueue()

        XCTAssertTrue(durations().isEmpty)
    }

    /// The interrupted-launch guard applies on the native path too, where the observer delivers.
    func testDidBecomeActive_whenLaunchInterrupted_doesNotReport() {
        launch.launchWasInterrupted = true
        sut.startMonitoring()
        drainMainQueue()
        sut.launchStartTime = CFAbsoluteTimeGetCurrent() - 1
        let durations = recordColdDurations()

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertTrue(durations().isEmpty)
    }

    /// Started by the system (silent push) and opened a few seconds later: a plausible-looking
    /// value that is not a launch, so the cap alone would let it through.
    func testStartMonitoring_whenStartedInBackground_doesNotReport() throws {
        let processStart = try XCTUnwrap(ColdDetector.processStartTime(), "sysctl unavailable")
        launch.firstActivation = processStart + 4
        launch.launchStartedInBackground = true
        let durations = recordColdDurations()

        sut.startMonitoring()
        drainMainQueue()

        XCTAssertTrue(durations().isEmpty)
    }

    /// The prewarm guard still applies when the activation comes from the recorder.
    func testStartMonitoring_whenFirstActivationRecordedAndPrewarmed_doesNotReport() throws {
        let processStart = try XCTUnwrap(ColdDetector.processStartTime(), "sysctl unavailable")
        launch.firstActivation = processStart + 0.5
        sut.isPrewarmedLaunch = { true }
        let durations = recordColdDurations()

        sut.startMonitoring()
        drainMainQueue()

        XCTAssertTrue(durations().isEmpty)
    }

    /// A re-init in the same process finds the launch already claimed and reports nothing, so one
    /// launch yields one cold start however many times the SDK is initialized.
    func testStartMonitoring_whenLaunchAlreadyClaimed_doesNotReport() throws {
        let processStart = try XCTUnwrap(ColdDetector.processStartTime(), "sysctl unavailable")
        launch.firstActivation = processStart + 0.5
        launch.claimGranted = false
        let durations = recordColdDurations()

        sut.startMonitoring()
        drainMainQueue()

        XCTAssertTrue(durations().isEmpty)
        XCTAssertEqual(launch.claimCount, 1)
    }

    /// `stopMonitoring()` (SDK shutdown) leaves no observer behind to report a later activation.
    func testStopMonitoring_removesActivationObserver() {
        sut.startMonitoring()
        drainMainQueue()
        sut.launchStartTime = CFAbsoluteTimeGetCurrent() - 1
        let durations = recordColdDurations()

        sut.stopMonitoring()
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertTrue(durations().isEmpty)
    }

    // MARK: - CRXLaunchRecorder

    /// The claim is granted at most once per process. The first call may already have happened
    /// (other suites initialize the SDK), so only the second call's answer is fixed.
    ///
    /// This spends the real process-wide claim: a future test that initializes the SDK and expects
    /// a real `cold` span must not depend on running before this one — inject a
    /// `FakeLaunchRecording` instead.
    func testLaunchRecorder_claimIsGrantedOnlyOnce() {
        _ = CRXLaunchRecorder.claimColdStartReport()
        XCTAssertFalse(CRXLaunchRecorder.claimColdStartReport())
    }

    /// The background-start check fails open: only the roles a system start is known to get are
    /// dropped, and a user launch or any unclassified role keeps its cold start. A silent-push
    /// launch on the simulator reads `TASK_BACKGROUND_APPLICATION`; a home-screen tap reads
    /// `TASK_FOREGROUND_APPLICATION`.
    func testLaunchRecorder_classifiesOnlyKnownSystemStartRolesAsBackground() {
        for role in [TASK_BACKGROUND_APPLICATION, TASK_DARWINBG_APPLICATION, TASK_NONUI_APPLICATION] {
            XCTAssertTrue(CRXLaunchRecorder.isSystemStartTaskRole(Int(role.rawValue)), "role \(role.rawValue)")
        }
        let kept = [TASK_FOREGROUND_APPLICATION, TASK_UNSPECIFIED, TASK_CONTROL_APPLICATION,
                    TASK_GRAPHICS_SERVER, TASK_THROTTLE_APPLICATION, TASK_DEFAULT_APPLICATION]
            .map { Int($0.rawValue) } + [Int(TASK_RENICED.rawValue), 99]
        for role in kept {
            XCTAssertFalse(CRXLaunchRecorder.isSystemStartTaskRole(role), "role \(role)")
        }
    }

    /// `+load` armed the recorder: the first activation in this process is stamped, and later
    /// activations leave the stamp untouched.
    func testLaunchRecorder_stampsFirstActivationOnly() {
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(CRXLaunchRecorder.hasRecordedFirstActivation, "+load did not arm the recorder")
        let first = CRXLaunchRecorder.firstDidBecomeActiveTime
        XCTAssertLessThanOrEqual(first, CFAbsoluteTimeGetCurrent())

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(CRXLaunchRecorder.firstDidBecomeActiveTime, first)
    }

    /// Backgrounding after the first activation is a normal warm cycle, so it must not mark the
    /// launch as interrupted.
    func testLaunchRecorder_backgroundAfterFirstActivation_isNotAnInterruptedLaunch() {
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let interruptedBefore = CRXLaunchRecorder.launchWasInterrupted

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(CRXLaunchRecorder.launchWasInterrupted, interruptedBefore)
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
