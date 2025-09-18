//
//  SlowFrozenFramesDetector.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 14/08/2025.
//

import Foundation
import UIKit

final class SlowFrozenFramesDetector {
  
    // MARK: - Configuration
    private let frozenThresholdMs: Double         // e.g. 700ms
    private let reportIntervalMs: Int64           // e.g. 60_000
    private let tolerancePercentage: Double       // e.g. 0.03 (3%)

    // MARK: - State
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var refreshRateHz: Double = 60.0      // dynamic; updated on start / app active
    private var slowBudgetMs: Double = 16.7       // computed from refresh rate

    private let statsLock = NSLock()
    private var slowCount: Int = 0
    private var frozenCount: Int = 0
    private var sumFrameMs: Double = 0.0
    private var frameSamples: Int = 0

    private var reporterTimer: DispatchSourceTimer?
    private let reporterQueue = DispatchQueue(label: Keys.queueSlowFrozenReporterQueue.rawValue, qos: .utility)
    private var running = false
    private let lifecycleCenter = NotificationCenter.default
    
    // MARK: - Stored window results (one entry per report window)
    internal var windowSlow: [Int] = []      // number of slow frames in a window
    internal var windowFrozen: [Int] = []    // number of frozen frames in a window
    
    // MARK: - Public stats (computed over stored windows)
    // Slow
    var minSlow: Double { Double(windowSlow.min() ?? 0) }
    var maxSlow: Double { Double(windowSlow.max() ?? 0) }
    var avgSlow: Double { windowSlow.isEmpty ? 0 : Double(windowSlow.reduce(0, +)) / Double(windowSlow.count) }
    var p95Slow: Double { percentile95D(of: windowSlow.map(Double.init)) }
    
    // Frozen
    var minFrozen: Double { Double(windowFrozen.min() ?? 0) }
    var maxFrozen: Double { Double(windowFrozen.max() ?? 0) }
    var avgFrozen: Double { windowFrozen.isEmpty ? 0 : Double(windowFrozen.reduce(0, +)) / Double(windowFrozen.count) }
    var p95Frozen: Double { percentile95D(of: windowFrozen.map(Double.init)) }
    
    
    
    // MARK: - Init
    init(
        frozenThresholdMs: Double = 700.0,
        reportIntervalMs: Int64 = 60_000,
        tolerancePercentage: Double = 0.03
    ) {
        self.frozenThresholdMs = frozenThresholdMs
        self.reportIntervalMs = reportIntervalMs
        self.tolerancePercentage = tolerancePercentage
        updateRefreshRateAndBudget()
    }

    // MARK: - Public API
    public func startMonitoring() {
        guard !running else { return }
        running = true

        // Observe app becoming active to refresh Hz if ProMotion / external display changes.
        lifecycleCenter.addObserver(self,
                                    selector: #selector(appBecameActive),
                                    name: UIApplication.didBecomeActiveNotification,
                                    object: nil)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateRefreshRateAndBudget()
            let link = CADisplayLink(target: self, selector: #selector(self.onFrame(_:)))
            // Keep true-to-native frame pacing; on iOS 15+ you could set preferredFrameRateRange.
            // link.preferredFramesPerSecond = 0 // default: use native
            link.add(to: .main, forMode: .common) // fire during scrolling/gestures
            self.displayLink = link
            self.lastFrameTimestamp = 0
            Log.d("[Metric] slow/frozen frames monitor started @ \(self.refreshRateHz)Hz (budget=\(String(format: "%.2f", self.slowBudgetMs))ms)")
        }

        // Start periodic reporter on background queue
        let timer = DispatchSource.makeTimerSource(flags: [], queue: reporterQueue)
        timer.schedule(deadline: .now() + .milliseconds(Int(reportIntervalMs)),
                       repeating: .milliseconds(Int(reportIntervalMs)))
        timer.setEventHandler { [weak self] in
            self?.emitWindow()
        }
        timer.resume()
        reporterTimer = timer
    }

    public func stopMonitoring() {
        guard running else { return }
        running = false

        lifecycleCenter.removeObserver(self,
                                       name: UIApplication.didBecomeActiveNotification,
                                       object: nil)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.displayLink?.invalidate()
            self.displayLink = nil
            Log.d("slow/frozen frames monitor stopped")
        }

        reporterTimer?.cancel()
        reporterTimer = nil

        // Optional: flush remaining counts once on stop
        emitWindow()
        reset()
    }
    
    public func reset() {
        windowSlow.removeAll()
        windowFrozen.removeAll()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Frame callback
    @objc private func onFrame(_ link: CADisplayLink) {
        guard running else {
            lastFrameTimestamp = link.timestamp
            return
        }
        let ts = link.timestamp // seconds
        if lastFrameTimestamp != 0 {
            let dtMs = (ts - lastFrameTimestamp) * 1000.0

            statsLock.lock()
            sumFrameMs += dtMs
            frameSamples += 1
            let allowedDeviation = slowBudgetMs * tolerancePercentage
            if dtMs >= frozenThresholdMs {
                frozenCount += 1
            } else if dtMs > (slowBudgetMs + allowedDeviation) {
                slowCount += 1
                // Log.d("slow frame detected: \(dtMs)")
            }
            statsLock.unlock()
        }
        lastFrameTimestamp = ts
    }

    // MARK: - Reporting (grouped window)
    /// Snapshot & reset counts, then post metrics (skip if both zero).
    private func emitWindow() {
        var slow = 0
        var frozen = 0

        statsLock.lock()
        slow = slowCount
        frozen = frozenCount
       
        // reset window
        slowCount = 0
        frozenCount = 0
        sumFrameMs = 0
        frameSamples = 0
        statsLock.unlock()

        if slow == 0 && frozen == 0 { return }

        
        // Store this window’s counts (independently; skip zeros for each metric)
        if slow > 0 { windowSlow.append(slow) }
        if frozen > 0 { windowFrozen.append(frozen) }

//        Log.d("[Metric] slow: \(slow), frozen: \(frozen)")
    }
    
    func statsDictionary() -> [String: Any] {
        return [
            MobileVitalsType.slowFrames.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.count.stringValue,
                Keys.min.rawValue: minSlow,
                Keys.max.rawValue: maxSlow,
                Keys.avg.rawValue: avgSlow,
                Keys.p95.rawValue: p95Slow
            ],
            MobileVitalsType.frozenFrames.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.count.stringValue,
                Keys.min.rawValue: minFrozen,
                Keys.max.rawValue: maxFrozen,
                Keys.avg.rawValue: avgFrozen,
                Keys.p95.rawValue: p95Frozen
            ]
        ]
    }

    // MARK: - Refresh rate
    @objc private func appBecameActive() {
        // Display characteristics may change (external display, ProMotion changes)
        updateRefreshRateAndBudget()
        // Reset baseline to avoid counting one large idle gap as slow/frozen.
        lastFrameTimestamp = 0
    }

    private func updateRefreshRateAndBudget() {
        // Prefer UIScreen.main.maximumFramesPerSecond for the active display
        let hz: Int
        if #available(iOS 10.3, *) {
            hz = max(UIScreen.main.maximumFramesPerSecond, 60)
        } else {
            hz = 60
        }
        refreshRateHz = Double(hz)
        slowBudgetMs = 1000.0 / refreshRateHz
    }
    
    private func percentile95D(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int(ceil(0.95 * Double(sorted.count)))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }
}

