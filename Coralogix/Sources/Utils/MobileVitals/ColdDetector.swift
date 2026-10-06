//
//  ColdDetector.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 15/09/2025.
//

import Darwin
import Foundation
import UIKit
#if canImport(CoralogixBootstrap)
// SPM builds the bootstrap as its own module; under CocoaPods it is part of this pod.
import CoralogixBootstrap
#endif

/// What `CRXLaunchRecorder` observed about this process's launch. A protocol so tests can supply a
/// launch instead of inheriting the test host's.
protocol LaunchRecording {
    var firstActivation: CFAbsoluteTime? { get }
    var launchWasInterrupted: Bool { get }
    var launchStartedInBackground: Bool { get }
    var launchTaskRole: Int? { get }
    func claimColdStartReport() -> Bool
}

struct RecorderLaunchRecording: LaunchRecording {
    var firstActivation: CFAbsoluteTime? {
        CRXLaunchRecorder.hasRecordedFirstActivation ? CRXLaunchRecorder.firstDidBecomeActiveTime : nil
    }
    var launchWasInterrupted: Bool { CRXLaunchRecorder.launchWasInterrupted }
    var launchStartedInBackground: Bool { CRXLaunchRecorder.launchStartedInBackground }
    var launchTaskRole: Int? { CRXLaunchRecorder.launchTaskRole?.intValue }
    func claimColdStartReport() -> Bool { CRXLaunchRecorder.claimColdStartReport() }
}

final class ColdDetector {
    // Launches longer than this are background/prewarm artifacts (the process was spawned
    // long before the user foregrounded the app), not a user-perceived cold start. Dropping
    // them keeps multi-hour bogus values out of the Cold Start AVG.
    static let maxReasonableColdStartMs: Double = 60_000

    var launchStartTime: CFAbsoluteTime?
    var launchEndTime: CFAbsoluteTime?
    var handleColdClosure: (([String: Any]) -> Void)?

    /// Whether iOS prewarmed (background-spawned) this process ahead of user intent.
    /// In production it reads the OS `ActivePrewarm` env var; overridable in tests.
    var isPrewarmedLaunch: () -> Bool = {
        ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
    }

    private let launchRecording: LaunchRecording

    init(launchRecording: LaunchRecording = RecorderLaunchRecording()) {
        self.launchRecording = launchRecording
    }

    func startMonitoring() {
        // Use kernel process birth time for the most accurate cold-start start point.
        // Falls back to the current time (SDK init) if the syscall is unavailable.
        if let kernelStartTime = ColdDetector.processStartTime() {
            self.launchStartTime = kernelStartTime
        } else {
            Log.w("ColdDetector: sysctl failed to read process start time, falling back to SDK init time")
            self.launchStartTime = CFAbsoluteTimeGetCurrent()
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)

        // A late init (React Native, Flutter) finds the first activation already recorded and
        // reports it from here instead of waiting for the next activation, which would measure a
        // re-activation. Deferring to the next main-queue turn keeps the report out of SDK init, so
        // it never depends on the metrics collector being wired first, and it also catches an
        // off-main init that raced the activation past the observer above.
        DispatchQueue.main.async { [weak self] in
            guard let self, let firstActivation = self.launchRecording.firstActivation else { return }
            self.stopMonitoring()
            self.reportColdStart(activationTime: firstActivation)
        }
    }

    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.didBecomeActiveNotification,
                                                  object: nil)
    }

    @objc private func appDidBecomeActive() {
        // Remove the observer unconditionally on first delivery so it never
        // leaks into subsequent foreground cycles regardless of guard outcome.
        stopMonitoring()

        // Prefer the recorder's stamp: if init raced the first activation, this delivery may be a
        // later one, and only the first activation ends the launch.
        reportColdStart(activationTime: launchRecording.firstActivation ?? CFAbsoluteTimeGetCurrent())
    }

    private func reportColdStart(activationTime: CFAbsoluteTime) {
        guard let launchStartTime = self.launchStartTime,
              self.launchEndTime == nil else { return }

        self.launchEndTime = activationTime

        // A prewarmed process is spawned in the background before the user opens the app,
        // so the kernel birth time → didBecomeActive delta isn't a real cold start. Skip it.
        guard !isPrewarmedLaunch() else {
            Log.d("ColdDetector: prewarmed launch — skipping cold-start metric")
            return
        }

        // Started by the system (silent push, background fetch) and opened later: the delta
        // includes the time the process sat in the background.
        guard !launchRecording.launchStartedInBackground else {
            Log.d("ColdDetector: process started in the background (task role \(launchRecording.launchTaskRole.map(String.init) ?? "unread")) — skipping cold-start metric")
            return
        }

        // The user left during the launch: the delta includes the time away, and the return is
        // already reported as a warm start.
        guard !launchRecording.launchWasInterrupted else {
            Log.d("ColdDetector: launch interrupted before first activation — skipping cold-start metric")
            return
        }

        let epochStartTime = Helper.convertCFAbsoluteTimeToEpoch(launchStartTime)
        let epochEndTime = Helper.convertCFAbsoluteTimeToEpoch(activationTime)
        let duration = calculateTime(start: epochStartTime, stop: epochEndTime)

        // Backstop for background starts the task role cannot classify, which show the same
        // multi-hour skew. Drop anything beyond the sane ceiling rather than emit it.
        guard duration <= ColdDetector.maxReasonableColdStartMs else {
            Log.d("ColdDetector: cold-start duration \(duration)ms exceeds cap — likely a background launch, dropping")
            return
        }

        // Taken last, so it is spent only on a report that is actually emitted.
        guard launchRecording.claimColdStartReport() else {
            Log.d("ColdDetector: this launch was already reported by an earlier SDK init")
            return
        }

        let cold = [
            MobileVitalsType.cold.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.milliseconds.stringValue,
                Keys.value.rawValue: duration
            ]
        ]
        handleColdClosure?(cold)
    }

    func calculateTime(start: Double, stop: Double) -> Double {
        return max(0, stop - start)
    }

    /// Reads the process birth time from the kernel via `sysctl(KERN_PROC_PID)`.
    ///
    /// The kernel records the exact moment the OS spawned the process — before `main()` runs —
    /// giving a more accurate cold-start start point than any time recorded inside the app.
    /// Returns `nil` if the syscall fails; callers should fall back to `CFAbsoluteTimeGetCurrent()`.
    static func processStartTime() -> CFAbsoluteTime? {
        var kip = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &kip, &size, nil, 0) == 0 else { return nil }

        let tv = kip.kp_proc.p_starttime
        // tv_sec / tv_usec are relative to Unix epoch (1 Jan 1970).
        // Subtract kCFAbsoluteTimeIntervalSince1970 to align with CFAbsoluteTime (1 Jan 2001).
        let unixTime = Double(tv.tv_sec) + Double(tv.tv_usec) / Double(USEC_PER_SEC)
        return unixTime - kCFAbsoluteTimeIntervalSince1970
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
