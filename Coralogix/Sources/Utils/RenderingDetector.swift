//
//  RenderingDetector.swift
//
//
//  Created by Coralogix DEV TEAM on 08/09/2024.
//

import UIKit

class FPSMonitor {
    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0
    var startTime: CFTimeInterval = 0
    
    // Start monitoring FPS
    func startMonitoring() {
        displayLink = CADisplayLink(target: self, selector: #selector(trackFrame))
        displayLink?.add(to: .main, forMode: .common)
        frameCount = 0
        startTime = CACurrentMediaTime()
    }
    
    // Stop monitoring FPS and return average FPS
    func stopMonitoring() -> Double {
        displayLink?.invalidate()
        displayLink = nil
        let elapsedTime = CACurrentMediaTime() - startTime
        return Double(frameCount) / elapsedTime
    }
    
    @objc internal func trackFrame() {
        frameCount += 1
    }
}

class FPSTrigger {
    private let fpsMonitor = FPSMonitor()
    internal var timer: Timer?
    internal var isRunning = false
    static let defaultInterval = 300 // 5 min
    
    func startMonitoring(xTimesPerHour: Int = defaultInterval) {
        if !isRunning {
            isRunning = true
            var timesPerHour = xTimesPerHour
            if timesPerHour < FPSTrigger.defaultInterval {
                timesPerHour = FPSTrigger.defaultInterval
            }
            // Time interval between each trigger in seconds
            let interval = 3600 / timesPerHour
            
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
                self?.monitorFPS()
            }
        }
    }
    
    private func monitorFPS() {
        Log.d("[Metric] Starting FPS monitoring for 5 seconds...")
        
        // Start FPS monitoring
        fpsMonitor.startMonitoring()
        
        // Stop monitoring after 5 seconds and log the average FPS
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            let averageFPS = Int(self.fpsMonitor.stopMonitoring())
            Log.d("[Metric] Average FPS over 5 seconds: \(averageFPS)")
            
            // send instrumentaion event
            NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                            object: CXMobileVitals(type: .fps, value: "\(averageFPS)"))
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
}

enum CXMobileVitalsType: String {
    case cold
    case warm
    case fps
    case anr
    case metricKit
}

struct CXMobileVitals {
    let type: CXMobileVitalsType
    let value: String
}
