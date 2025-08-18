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
        var avg: Double = 0
        var samples = 0

        statsLock.lock()
        slow = slowCount
        frozen = frozenCount
        if frameSamples > 0 {
            avg = sumFrameMs / Double(frameSamples)
        }
        // reset window
        slowCount = 0
        frozenCount = 0
        sumFrameMs = 0
        samples = frameSamples
        frameSamples = 0
        statsLock.unlock()

        if slow == 0 && frozen == 0 { return }

        let uuid = UUID().uuidString.lowercased()

        // Post two metrics with same UUID (mirrors Android grouped emission)
        func post(type: MobileVitalsType, value: Double, units: MeasurementUnits) {
            let payload = MobileVitals(
                type: type,
                name: type.stringValue,
                value: value,
                units: units,
                uuid: uuid
            )
            if Thread.isMainThread {
                NotificationCenter.default.post(name: .cxRumNotificationMetrics, object: payload)
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .cxRumNotificationMetrics, object: payload)
                }
            }
        }

        if slow > 0 { post(type: .slowFrames, value: Double(slow), units: .count) }
        if frozen > 0 { post(type: .frozenFrames, value: Double(frozen), units: .count) }

        Log.d("[Metric] avg frame: \(String(format: "%.2f", avg))ms from \(samples) samples, slow: \(slow), frozen: \(frozen), budget: \(String(format: "%.2f", slowBudgetMs))ms")
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
}

