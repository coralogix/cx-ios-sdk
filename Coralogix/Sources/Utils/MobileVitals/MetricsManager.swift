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
    
    public func addObservers() {
        MXMetricManager.shared.add(MyMetricSubscriber.shared)
    }
    
    public func removeObservers() {
        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
        self.stopAllDetectors()
    }
    
    func startMonitoring() {
        self.startColdStartMonitoring()
        self.fpsTrigger.startMonitoring()
        self.startCPUMonitoring()
        self.startMemoryMonitoring()
        self.startSlowFrozenFramesMonitoring()
    }
    
    func startColdStartMonitoring() {
        guard coldDetector == nil else { return }
        let detector = ColdDetector()
        detector.startMonitoring()
        self.coldDetector = detector
    }
    
    func startWarmStartMonitoring() {
        guard warmDetector == nil else { return }
        let detector = WarmDetector()
        detector.startMonitoring()
        self.warmDetector = detector
    }
    
    func startANRMonitoring() {
        self.anrDetector = ANRDetector()
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
    
    deinit {
        self.stopAllDetectors()
    }
}
  
class MyMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = MyMetricSubscriber()

    // Handle received metrics
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let metricPayloadJsonString = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                Log.d("metricPayloadJsonString  \(metricPayloadJsonString)")
                // send instrumentaion event
                NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                                object: MobileVitals(type: .metricKit,
                                                                     name: metricPayloadJsonString,
                                                                     value: 0.0,
                                                                     units: MeasurementUnits(from: "")))
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
