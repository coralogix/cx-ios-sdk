//
//  CPUDetector.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 12/08/2025.
//

import Foundation
import Darwin.Mach

/// CPU usage of *your app* as a % of total device CPU (all cores).
public final class CPUDetector {
    private var timer: Timer?
    
    // Time interval to check for CPU (e.g., every 1 second)
    private let checkInterval: TimeInterval
    private var lastProcSeconds: Double?
    private var lastWallSeconds: Double?
    private let cpuCount = Double(ProcessInfo.processInfo.activeProcessorCount)
    private var timebase = mach_timebase_info_data_t()
    private let minInterval: TimeInterval = 0.1

    public init(checkInterval: TimeInterval = 1.0) {
        mach_timebase_info(&timebase)
        var interval = checkInterval
        if interval < minInterval {
            interval = minInterval
        }
        self.checkInterval = interval
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(timeInterval: checkInterval,
                                     target: self,
                                     selector: #selector(checkForCPU),
                                     userInfo: nil,
                                     repeats: true)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    @objc private func checkForCPU() {
        if let sample = self.samplePercent() {
            Log.d(String(format: "[Metric] App CPU: %.3f%% | Total CPU Time: %.3f ms | Main Thread Time: %.3f ms",
                         sample.usagePercent,
                         sample.totalCpuTimeMs,
                         sample.mainThreadTimeMs))
        }
    }

    public func samplePercent() -> (usagePercent: Double, totalCpuTimeMs: Double, mainThreadTimeMs: Double)? {
        guard let proc = currentProcessCPUSeconds(),
                let mainMs = mainThreadCpuTimeMs() else { return nil }
        let wall = nowSeconds()

        defer {
            lastProcSeconds = proc
            lastWallSeconds = wall
        }
        guard let lp = lastProcSeconds, let lw = lastWallSeconds else { return nil }

        let dProc = max(0, proc - lp)
        let dWall = max(1e-6, wall - lw)

        // % of total CPU across all cores
        let pct = (dProc / (dWall * cpuCount)) * 100.0
        
        // Convert total process CPU time (seconds) → ms
        let totalCpuTimeMs = proc * 1000.0

        let usagePercent = min(max(pct, 0), 100) // clamp to [0,100]
        return (usagePercent: usagePercent, totalCpuTimeMs: totalCpuTimeMs, mainThreadTimeMs: mainMs)
    }

    // MARK: - Internals

    private func nowSeconds() -> Double {
        let t = mach_absolute_time()
        let nanos = (t &* UInt64(timebase.numer)) / UInt64(timebase.denom)
        return Double(nanos) / 1_000_000_000.0
    }

    private func currentProcessCPUSeconds() -> Double? {
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = task_basic_info_data_t()

        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let sys  = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + sys
    }
    
    /// Returns main thread CPU time in milliseconds
    func mainThreadCpuTimeMs() -> Double? {
        var info = thread_basic_info_data_t()
        var count = mach_msg_type_number_t(THREAD_INFO_MAX)

        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(mach_thread_self(),
                            thread_flavor_t(THREAD_BASIC_INFO),
                            $0,
                            &count)
            }
        }

        guard kr == KERN_SUCCESS else { return nil }

        let userSec = Double(info.user_time.seconds)
        let userMicro = Double(info.user_time.microseconds)
        let sysSec = Double(info.system_time.seconds)
        let sysMicro = Double(info.system_time.microseconds)

        let totalMs = (userSec + sysSec) * 1000.0 + (userMicro + sysMicro) / 1000.0
        return totalMs
    }
}
