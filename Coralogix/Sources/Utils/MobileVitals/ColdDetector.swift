//
//  ColdDetector.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 15/09/2025.
//

import Darwin
import Foundation
import UIKit

final class ColdDetector {
    var launchStartTime: CFAbsoluteTime?
    var launchEndTime: CFAbsoluteTime?
    var handleColdClosure: (([String: Any]) -> Void)?

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
    }

    @objc private func appDidBecomeActive() {
        guard let launchStartTime = self.launchStartTime,
              self.launchEndTime == nil else { return }

        let launchEndTime = CFAbsoluteTimeGetCurrent()
        self.launchEndTime = launchEndTime

        // Cold start fires exactly once — remove the observer immediately.
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.didBecomeActiveNotification,
                                                  object: nil)

        let epochStartTime = Helper.convertCFAbsoluteTimeToEpoch(launchStartTime)
        let epochEndTime = Helper.convertCFAbsoluteTimeToEpoch(launchEndTime)
        let duration = calculateTime(start: epochStartTime, stop: epochEndTime)

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
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &kip, &size, nil, 0) == 0 else { return nil }

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
