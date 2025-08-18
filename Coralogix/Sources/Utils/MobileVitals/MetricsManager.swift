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
    var launchStartTime: CFAbsoluteTime?
    var launchEndTime: CFAbsoluteTime?
    var foregroundStartTime: CFAbsoluteTime?
    var foregroundEndTime: CFAbsoluteTime?
    var anrDetector: ANRDetector?
    var cpuDetector: CPUDetector?
    var memoryDetector: MemoryDetector?
    var slowFrozenFramesDetector: SlowFrozenFramesDetector?
    var fpsTrigger = FPSTrigger()
    let mobileVitalsFPSSamplingRate = 300 // 5 min
    var warmMetricIsActive = false
    
    public func addObservers() {
        MXMetricManager.shared.add(MyMetricSubscriber.shared)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.handleNotification(notification:)),
                                               name: .cxViewDidAppear,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.appDidEnterBackgroundNotification),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        let sdk = CoralogixRum.mobileSDK.sdkFramework

        // Warm
        switch sdk {
        case .flutter, .reactNative:
            // it's flutter or react-native
            break
        case .swift:
            // it's not flutter or react-native
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.appWillEnterForegroundNotification),
                                                   name: UIApplication.willEnterForegroundNotification,
                                                   object: nil)
            
            NotificationCenter.default.addObserver(self, selector: #selector(self.appDidBecomeActiveNotification),
                                                   name: UIApplication.didBecomeActiveNotification,
                                                   object: nil)
        }
    }
    
    public func removeObservers() {
        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
        self.stopAllDetectors()
    }
    
    func startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: Int) {
        self.fpsTrigger.startMonitoring(xTimesPerHour: mobileVitalsFPSSamplingRate)
    }
    
    @objc func appDidEnterBackgroundNotification() {
        self.stopAllDetectors()
        self.warmMetricIsActive = true
    }
    
    // Warm
    @objc internal func appWillEnterForegroundNotification() {
        Log.d("App Will Enter Foreground")
        if warmMetricIsActive == true {
            self.foregroundStartTime = CFAbsoluteTimeGetCurrent()
            self.foregroundEndTime = nil
            self.warmMetricIsActive = false
        }
    }
    
    @objc internal func appDidBecomeActiveNotification() {
        Log.d("App did Become Active")
        if let foregroundStartTime = self.foregroundStartTime,
           self.foregroundEndTime == nil {
            let currentTime = CFAbsoluteTimeGetCurrent()
            self.foregroundEndTime = currentTime
            let warmStartDuration = currentTime - foregroundStartTime
            
            let warmStartRounded = warmStartDuration * 1000
            
            // Convert to an integer if you want to remove the decimal part
            Log.d("[Metric] Warm start duration: \(warmStartRounded) milliseconds")
            
            // send instrumentaion event
            NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                            object: MobileVitals(type: .warm,
                                                                 value: warmStartRounded,
                                                                 units: .milliseconds))
        }
        
        // Resume mobile vitals monitoring
        self.startANRMonitoring()
        self.startCPUMonitoring()
        self.startMemoryMonitoring()
        self.startSlowFrozenFramesMonitoring()
        self.startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: mobileVitalsFPSSamplingRate)
    }
    
    func startColdStartMonitoring() {
        self.launchStartTime = CFAbsoluteTimeGetCurrent()
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
    
    @objc func handleNotification(notification: Notification) {
        if let metrics = notification.object as? [String: Any] {
            if let launchStartTime = self.launchStartTime,
               let launchEndTime = metrics[MobileVitalsType.cold.stringValue] as? CFAbsoluteTime,
               self.launchEndTime == nil {
                self.launchEndTime = launchEndTime
                let epochStartTime = Helper.convertCFAbsoluteTimeToEpoch(launchStartTime)
                let epochEndTime = Helper.convertCFAbsoluteTimeToEpoch(launchEndTime)
                let millisecondsRounded = self.calculateTime(start: epochStartTime, stop: epochEndTime)

                NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                                object: MobileVitals(type: .cold,
                                                                     value: millisecondsRounded,
                                                                     units: .milliseconds))
            }
        }
    }
    
    func calculateTime(start: Double, stop: Double) -> Double {
        let coldStartDurationInSeconds = stop - start
        let coldStartDurationInMilliseconds = coldStartDurationInSeconds
        return coldStartDurationInMilliseconds
    }
    
    internal func getWarmTime(params: [String: Any]) -> MobileVitals? {
        if let warmTime = params[MobileVitalsType.warm.stringValue] as? Double {
            return MobileVitals(type: .warm, value: warmTime, units: .milliseconds)
        }
        
        return nil
    }
    
    internal func getColdTime(params: [String: Any]) -> MobileVitals? {
        guard let startTime = self.launchStartTime else {
            return nil
        }
        
        let launchStartTime = Helper.convertCFAbsoluteTimeToEpoch(startTime)

        if let nativeLaunchEnd = params[MobileVitalsType.cold.stringValue] as? Double {
            let duration = calculateTime(start: launchStartTime, stop: nativeLaunchEnd)
            return MobileVitals(type: .cold, value: duration, units: .milliseconds)
        }
        
        return nil
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
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxViewDidAppear, object: nil)
        
        self.stopAllDetectors()
        self.launchEndTime = 0
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
