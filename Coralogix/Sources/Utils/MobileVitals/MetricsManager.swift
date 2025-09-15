//
//  MetricsManager.swift
//
//
//  Created by Coralogix DEV TEAM on 08/08/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import MetricKit
import CoralogixInternal

public class MetricsManager {
    var coldDetector: ColdDetector?
    var warmDetector: WarmDetector?
    var anrDetector: ANRDetector?
    var cpuDetector: CPUDetector?
    var memoryDetector: MemoryDetector?
    var slowFrozenFramesDetector: SlowFrozenFramesDetector?
    var fpsTrigger = FPSTrigger()
    var metricsManagerClosure: (([String: Any]) -> Void)?
    
    // MARK: - Internal timer for periodic send
    private var sendTimer: Timer?
    private let sendInterval: TimeInterval = 15.0
    private var lastSendTime: Date?
    private var schedulingActive = false
    
    public func addMatricKitObservers() {
        MyMetricSubscriber.shared.metricKitClosure = { [weak self] dict in
            self?.metricsManagerClosure?(dict)
        }
        MXMetricManager.shared.add(MyMetricSubscriber.shared)
    }
    
    public func removeObservers() {
        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
        self.stopAllDetectors()
        self.stopSendTimer()
    }
    
    public func sendMobileVitals() {
        let now = Date()
        if let last = lastSendTime, now.timeIntervalSince(last) < sendInterval {
            Log.d("[MetricsManager] Skipped sendMobileVitals(), only \(now.timeIntervalSince(last))s since last event")
            return
        }
        
        var vitals = [String: Any]()
        if let cpuDetector = cpuDetector {
            vitals[Keys.cpu.rawValue] = cpuDetector.statsDictionary()
        }
        
        if let memoryDetector = memoryDetector {
            vitals[Keys.memory.rawValue] = memoryDetector.statsDictionary()
        }
        
        if let slowFrozenFramesDetector = slowFrozenFramesDetector {
            vitals[Keys.slowFrozen.rawValue] = slowFrozenFramesDetector.statsDictionary()
        }
        
        vitals[MobileVitalsType.fps.stringValue] = fpsTrigger.statsDictionary()
        
        // Send event
        self.metricsManagerClosure?(vitals)
        lastSendTime = Date()

        // Reset stats after sending
        cpuDetector?.reset()
        memoryDetector?.reset()
        slowFrozenFramesDetector?.reset()
        fpsTrigger.reset()
    }
    
    func startMonitoring() {
        self.startColdStartMonitoring()
        self.fpsTrigger.startMonitoring()
        self.startCPUMonitoring()
        self.startMemoryMonitoring()
        self.startSlowFrozenFramesMonitoring()
        startSendScheduler()   // start periodic sending
    }
    
    func startColdStartMonitoring() {
        guard coldDetector == nil else { return }
        let detector = ColdDetector()
        detector.handleColdClosure = { [weak self] dict in
            self?.metricsManagerClosure?(dict)
        }
        detector.startMonitoring()
        self.coldDetector = detector
    }
    
    func startWarmStartMonitoring() {
        guard warmDetector == nil else { return }
        let detector = WarmDetector()
        detector.handleWarmClosure = { [weak self] dict in
            self?.metricsManagerClosure?(dict)
        }
        detector.startMonitoring()
        self.warmDetector = detector
    }
    
    func startANRMonitoring() {
        self.anrDetector = ANRDetector()
        self.anrDetector?.handleANRClosure = { [weak self] dict in
            self?.metricsManagerClosure?(dict)
        }
        self.anrDetector?.startMonitoring()
    }
    
    func startCPUMonitoring() {
        guard cpuDetector == nil else { return }
        let detector = CPUDetector()
        detector.startMonitoring()
        self.cpuDetector = detector
    }
    
    func startMemoryMonitoring() {
        guard memoryDetector == nil else { return }
        let detector = MemoryDetector()
        detector.startMonitoring()
        self.memoryDetector = detector
    }
    
    func startSlowFrozenFramesMonitoring() {
        guard slowFrozenFramesDetector == nil else { return }
        let detector = SlowFrozenFramesDetector()
        detector.startMonitoring()
        self.slowFrozenFramesDetector = detector
    }
    
    private func stopAllDetectors() {
        anrDetector?.stopMonitoring()
        anrDetector = nil
        cpuDetector?.stopMonitoring()
        cpuDetector = nil
        memoryDetector?.stopMonitoring()
        memoryDetector = nil
        slowFrozenFramesDetector?.stopMonitoring()
        slowFrozenFramesDetector = nil
        fpsTrigger.stopMonitoring()
    }
    
    private func startSendScheduler() {
        schedulingActive = true
        scheduleNextSendCheck()
    }
    
    private func stopSendScheduler() {
        schedulingActive = false
        // Nothing to cancel directly (we're not using a DispatchWorkItem),
        // but the guard in scheduleNextSendCheck() prevents further scheduling.
    }
    
    private func scheduleNextSendCheck() {
        guard schedulingActive else { return }
        
        DispatchQueue.main.asyncAfter(
            deadline: .now() + sendInterval,
            qos: .unspecified,
            flags: [],
            execute: { [weak self] in
                guard let self = self, self.schedulingActive else { return }
                
                let now = Date()
                if let last = self.lastSendTime {
                    if now.timeIntervalSince(last) >= self.sendInterval {
                        self.sendMobileVitals()
                    } else {
                        Log.d("[MetricsManager] Skipped send, only \(now.timeIntervalSince(last))s since last event")
                    }
                } else {
                    // First time we fire the scheduler
                    self.sendMobileVitals()
                }
                
                // Re-schedule the next check
                self.scheduleNextSendCheck()
            }
        )
    }

    
    private func stopSendTimer() {
        sendTimer?.invalidate()
        sendTimer = nil
    }

    deinit {
        self.stopAllDetectors()
        stopSendTimer()
    }
}
  
class MyMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = MyMetricSubscriber()
    var metricKitClosure: (([String: Any]) -> Void)?

    // Handle received metrics
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let metricPayloadJsonString = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                Log.d("metricPayloadJsonString  \(metricPayloadJsonString)")
                // send instrumentaion event
                let vital = [
                    Keys.metricKit.rawValue: [
                        Keys.name.rawValue: metricPayloadJsonString
                    ]
                ]
                self.metricKitClosure?(vital)
            }
                    
            if let applicationLaunchMetric = payload.applicationLaunchMetrics {
                Log.d("Launch Time: \(applicationLaunchMetric.histogrammedApplicationResumeTime)")
                Log.d("Time to First Draw: \(applicationLaunchMetric.histogrammedTimeToFirstDraw)")
            }
            
            if let diskWritesMetric = payload.diskIOMetrics {
                Log.d("Disk Writes: \(diskWritesMetric.cumulativeLogicalWrites)")
            }
            
            if let memoryMetric = payload.memoryMetrics {
                Log.d("Memory Usage: \(memoryMetric.averageSuspendedMemory)")
            }
        }
    }
    
    // Handle received diagnostics
    @available(iOS 14.0, *)
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let hangDiagnostics = payload.hangDiagnostics {
                for hangDiagnostic in hangDiagnostics {
                    Log.d("Call Stack Tree: \(hangDiagnostic.callStackTree)")
                }
            }
        }
    }
}
