//
//  RenderingDetector.swift
//
//
//  Created by Coralogix DEV TEAM on 08/09/2024.
//

import UIKit
import CoralogixInternal

class FPSMonitor {
    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0
    var startTime: CFTimeInterval = 0
    
    // Start monitoring FPS
    func startMonitoring() {
        guard displayLink == nil else { return }
        frameCount = 0
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(trackFrame))
        // If you want exact display refresh sampling, don't set preferredFramesPerSecond.
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    
    // Stop monitoring FPS and return average FPS
    func stopMonitoring() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    /// Returns FPS since last sample and resets the counters.
    func sampleAndReset() -> Double {
        let now = CACurrentMediaTime()
        let elapsed = now - startTime
        let fps = elapsed > 0 ? Double(frameCount) / elapsed : 0
        frameCount = 0
        startTime = now
        return fps
    }
    
    @objc internal func trackFrame() {
        frameCount += 1
    }
}

class FPSDetector {
    private let fpsMonitor = FPSMonitor()
    internal var timer: Timer?
    internal var isRunning = false
    static let defaultInterval: TimeInterval = 1.0 // second
    internal var samples: [Double] = []
    
    // MARK: - Public stats
    var minFPS: Double { samples.min() ?? 0 }
    var maxFPS: Double { samples.max() ?? 0 }
    var avgFPS: Double { samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count) }
    var p95FPS: Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let rank = Int(ceil(0.95 * Double(sorted.count)))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }
    
    func startMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.isRunning = true

            // Start the continuous display link once
            self.fpsMonitor.startMonitoring()
            startTimer()
            
            NotificationCenter.default.addObserver(self, selector: #selector(self.appDidBecomeActive),
                                                   name: UIApplication.didBecomeActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.appWillResignActive),
                                                   name: UIApplication.willResignActiveNotification, object: nil)
        }
    }
    
    private func startTimer() {
        stopTimer() // ensure only one timer at a time
        let t = Timer.scheduledTimer(withTimeInterval: FPSDetector.defaultInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let fps = self.fpsMonitor.sampleAndReset()
            if fps == 0 || fps.isNaN || fps.isInfinite { return }
            self.samples.append(fps)
//        Log.d("""
//        [FPS DEBUG] last=\(fps),
//        min=\(self.minFPS),
//        max=\(self.maxFPS),
//        avg=\(self.avgFPS),
//        p95=\(self.p95FPS)
//        """)
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self)
        stopTimer()
        fpsMonitor.stopMonitoring()
        isRunning = false
        reset()
    }
    
    public func reset() {
        samples.removeAll()
    }
    
    @objc private func appWillResignActive() {
        stopTimer()
    }
    
    @objc private func appDidBecomeActive() {
        guard isRunning else { return }
        _ = fpsMonitor.sampleAndReset()   // reset baseline to "now" so the first sample isn't skewed
        startTimer()
    }
    
    func statsDictionary() -> [String: Any] {
        return [
            Keys.mobileVitalsUnits.rawValue: MeasurementUnits.fps.stringValue,
            Keys.min.rawValue: minFPS,
            Keys.max.rawValue: maxFPS,
            Keys.avg.rawValue: avgFPS,
            Keys.p95.rawValue: p95FPS
        ]
    }
}
