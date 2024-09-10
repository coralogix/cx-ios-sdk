//
//  CXRenderingDetector.swift
//
//
//  Created by Coralogix DEV TEAM on 08/09/2024.
//

import UIKit

class CXFPSMonitor {
    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0
    private var startTime: CFTimeInterval = 0
    
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
    
    @objc private func trackFrame() {
        frameCount += 1
    }
}

class CXFPSTrigger {
    private let cxFpsMonitor = CXFPSMonitor()
    private var timer: Timer?
    private var isRunning = false
    
    func startMonitoring(xTimesPerHour: Int = 60) {
        if !isRunning {
            isRunning = true
            var timesPerHour = xTimesPerHour
            if timesPerHour < 60 {
                timesPerHour = 60
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
        cxFpsMonitor.startMonitoring()
        
        // Stop monitoring after 5 seconds and log the average FPS
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            let averageFPS = Int(self.cxFpsMonitor.stopMonitoring())
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
}

struct CXMobileVitals {
    let type: CXMobileVitalsType
    let value: String
}
