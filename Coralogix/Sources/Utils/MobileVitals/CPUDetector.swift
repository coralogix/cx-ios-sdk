//
//  CPUDetector.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 12/08/2025.
//

import Foundation
import Darwin.Mach
import UIKit

/// CPU usage of *your app* as a % of total device CPU (all cores).
final class CPUDetector {
    private var timer: Timer?
    internal var isRunning = false
    private var timebase = mach_timebase_info_data_t()

    // Time interval to check for CPU (e.g., every 1 second)
    internal let checkInterval: TimeInterval
    private let minInterval: TimeInterval = 0.1

    private var lastProcSeconds: Double?
    private var lastWallSeconds: Double?
    private var lastMainMs: Double?

    private let cpuCount = Double(ProcessInfo.processInfo.activeProcessorCount)
    var handleCpuClosure: (() -> Void)?
    
    // MARK: - Stored samples (per-interval)
    internal var usageSamples: [Double] = []          // percent 0...100
    internal var totalCpuDeltaMsSamples: [Double] = [] // process CPU delta ms in interval
    internal var mainThreadDeltaMsSamples: [Double] = [] // main-thread CPU delta ms in interval

    // MARK: - Public stats (computed over stored samples)
    // Usage %
    var minCPU: Double { usageSamples.min() ?? 0 }
    var maxCPU: Double { usageSamples.max() ?? 0 }
    var avgCPU: Double { usageSamples.isEmpty ? 0 : usageSamples.reduce(0, +) / Double(usageSamples.count) }
    var p95CPU: Double { percentile95(of: usageSamples) }
    
    // Total CPU time delta (ms)
    var minTotalCpuMs: Double { totalCpuDeltaMsSamples.min() ?? 0 }
    var maxTotalCpuMs: Double { totalCpuDeltaMsSamples.max() ?? 0 }
    var avgTotalCpuMs: Double { totalCpuDeltaMsSamples.isEmpty ? 0 : totalCpuDeltaMsSamples.reduce(0, +) / Double(totalCpuDeltaMsSamples.count) }
    var p95TotalCpuMs: Double { percentile95(of: totalCpuDeltaMsSamples) }
    
    // Main-thread CPU time delta (ms)
    var minMainThreadMs: Double { mainThreadDeltaMsSamples.min() ?? 0 }
    var maxMainThreadMs: Double { mainThreadDeltaMsSamples.max() ?? 0 }
    var avgMainThreadMs: Double { mainThreadDeltaMsSamples.isEmpty ? 0 : mainThreadDeltaMsSamples.reduce(0, +) / Double(mainThreadDeltaMsSamples.count) }
    var p95MainThreadMs: Double { percentile95(of: mainThreadDeltaMsSamples) }

    init(checkInterval: TimeInterval = 1.0) {
        mach_timebase_info(&timebase)
        self.checkInterval = max(checkInterval, minInterval)
    }
    
    public func startMonitoring() {
        DispatchQueue.main.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            
            self.lastProcSeconds = self.currentProcessCPUSeconds()
            self.lastWallSeconds = self.nowSeconds()
            self.lastMainMs = self.mainThreadCpuTimeMs()

            self.startTimer()
            
            NotificationCenter.default.addObserver(self, selector: #selector(self.appWillResignActive),
                                                   name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.appDidBecomeActive),
                                                   name: UIApplication.didBecomeActiveNotification, object: nil)
        }
    }

    public func stopMonitoring() {
        NotificationCenter.default.removeObserver(self)
        stopTimer()
        isRunning = false
        reset()
    }
    
    func reset() {
        usageSamples.removeAll()
        totalCpuDeltaMsSamples.removeAll()
        mainThreadDeltaMsSamples.removeAll()
    }
    
    deinit { stopMonitoring() }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let t = Timer.scheduledTimer(timeInterval: checkInterval,
                                     target: self,
                                     selector: #selector(tick),
                                     userInfo: nil,
                                     repeats: true)
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    @objc private func tick() {
        guard
            let proc = currentProcessCPUSeconds(),
            let wall = Optional(nowSeconds()),
            let mainNow = mainThreadCpuTimeMs()
        else { return }
     
        guard let lp = lastProcSeconds, let lw = lastWallSeconds, let lm = lastMainMs else {
            // Initialize baselines on first valid tick
            lastProcSeconds = proc
            lastWallSeconds = wall
            lastMainMs = mainNow
            return
        }
        // Compute deltas for this interval
        let dProc = max(0, proc - lp)         // seconds
        let dWall = max(1e-6, wall - lw)      // seconds
        let dMain = max(0, mainNow - lm)      // ms (already in ms)
        
        // Update baselines
        lastProcSeconds = proc
        lastWallSeconds = wall
        lastMainMs = mainNow
        // Per-interval metrics
        let usagePct = min(max((dProc / (dWall * cpuCount)) * 100.0, 0), 100)
        let totalCpuDeltaMs = dProc * 1000.0 // convert sec -> ms
        
        guard usagePct.isFinite, totalCpuDeltaMs.isFinite, dMain.isFinite else { return }
        
        usageSamples.append(usagePct)
        totalCpuDeltaMsSamples.append(totalCpuDeltaMs)
        mainThreadDeltaMsSamples.append(dMain)

//        Log.d(String(format:
//                        "[CPU DEBUG] usage=%.2f%% (min=%.2f max=%.2f avg=%.2f p95=%.2f) | totalΔ=%.2fms (min=%.2f max=%.2f avg=%.2f p95=%.2f) | mainΔ=%.2fms (min=%.2f max=%.2f avg=%.2f p95=%.2f)",
//                     usagePct, minCPU, maxCPU, avgCPU, p95CPU,
//                     totalCpuDeltaMs, minTotalCpuMs, maxTotalCpuMs, avgTotalCpuMs, p95TotalCpuMs,
//                     dMain, minMainThreadMs, maxMainThreadMs, avgMainThreadMs, p95MainThreadMs
//                    ))
    }
    
    // MARK: - App lifecycle observers (implementation you asked for)
    @objc private func appWillResignActive() {
        // Pause sampling to avoid giant background intervals
        stopTimer()
    }
    
    @objc private func appDidBecomeActive() {
        guard isRunning else { return }
        // Reset baselines so the first tick after resume has a clean delta
        lastProcSeconds = currentProcessCPUSeconds()
        lastWallSeconds = nowSeconds()
        lastMainMs = mainThreadCpuTimeMs()
        
        startTimer()
    }
    
    // MARK: - Internals

    private func nowSeconds() -> Double {
        let t = mach_absolute_time()
        let nanos = (t &* UInt64(timebase.numer)) / UInt64(timebase.denom)
        return Double(nanos) / 1_000_000_000.0
    }

    internal func currentProcessCPUSeconds() -> Double? {
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
        
        let thread = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, thread) }
        
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread,
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
    
    private func percentile95(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int(ceil(0.95 * Double(sorted.count)))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }
    
    func statsDictionary() -> [String: Any] {
        return [
            MobileVitalsType.cpuUsage.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.percentage.stringValue,
                Keys.min.rawValue: minCPU,
                Keys.max.rawValue: maxCPU,
                Keys.avg.rawValue: avgCPU,
                Keys.p95.rawValue: p95CPU
            ],
            MobileVitalsType.totalCpuTime.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.milliseconds.stringValue,
                Keys.min.rawValue: minTotalCpuMs,
                Keys.max.rawValue: maxTotalCpuMs,
                Keys.avg.rawValue: avgTotalCpuMs,
                Keys.p95.rawValue: p95TotalCpuMs
            ],
            MobileVitalsType.mainThreadCpuTime.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.milliseconds.stringValue,
                Keys.min.rawValue: minMainThreadMs,
                Keys.max.rawValue: maxMainThreadMs,
                Keys.avg.rawValue: avgMainThreadMs,
                Keys.p95.rawValue: p95MainThreadMs
            ]
        ]
    }
}
