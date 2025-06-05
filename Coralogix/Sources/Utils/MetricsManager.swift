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
        // Warm
        if !([.reactNative, .flutter].contains(CoralogixRum.sdkFramework)) {
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
    }
    
    func startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: Int) {
        self.fpsTrigger.startMonitoring(xTimesPerHour: mobileVitalsFPSSamplingRate)
    }
    
    @objc func appDidEnterBackgroundNotification() {
        self.fpsTrigger.stopMonitoring()
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
            
            let warmStartDurationInMilliseconds = warmStartDuration * 1000
            
            // Convert to an integer if you want to remove the decimal part
            let millisecondsRounded = Int(warmStartDurationInMilliseconds)
            Log.d("[Metric] Warm start duration: \(millisecondsRounded) milliseconds")
            
            // send instrumentaion event
            NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                            object: CXMobileVitals(type: .warm, value: "\(millisecondsRounded)"))
        }
    }
    
    func startColdStartMonitoring() {
        self.launchStartTime = CFAbsoluteTimeGetCurrent()
    }
    
    func startANRMonitoring() {
        self.anrDetector = ANRDetector()
        self.anrDetector?.startMonitoring()
    }
    
    @objc func handleNotification(notification: Notification) {
        if let metrics = notification.object as? [String: Any] {
            if let launchStartTime = self.launchStartTime,
               let launchEndTime = metrics[CXMobileVitalsType.cold.rawValue] as? CFAbsoluteTime,
               self.launchEndTime == nil {
                self.launchEndTime = launchEndTime
                let millisecondsRounded = self.calculateTime(start: launchStartTime, stop: launchEndTime)
                NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                                object: CXMobileVitals(type: .cold, value: "\(millisecondsRounded)"))
            }
        }
    }
    
    func calculateTime(start: Double, stop: Double) -> Int {
        let coldStartDurationInSeconds = stop - start
        let coldStartDurationInMilliseconds = coldStartDurationInSeconds * 1000
        return Int(coldStartDurationInMilliseconds)
    }
    
    internal func getCXMobileVitals(params: [String: Any]) -> CXMobileVitals? {
        let handlers: [CXMobileVitalsType: ([String: Any]) -> CXMobileVitals?] = [
            .cold: getColdTime,
            .warm: getWarmTime
        ]
        
        for (key, handler) in handlers {
            if params.keys.contains(key.rawValue) {
                return handler(params)
            }
        }
        return nil
    }
    
    internal func getWarmTime(params: [String: Any]) -> CXMobileVitals? {
        if let launchEndTime = params[CXMobileVitalsType.warm.rawValue] as? Double {
            let millisecondsRounded = Int(launchEndTime)
            return CXMobileVitals(type: .warm, value: "\(millisecondsRounded)")
        }
        return nil
    }
    
    internal func getColdTime(params: [String: Any]) -> CXMobileVitals? {
        if let launchStartTime = self.launchStartTime,
           let launchEndTime = params[CXMobileVitalsType.cold.rawValue] as? CFAbsoluteTime {
            self.launchEndTime = launchEndTime
            let millisecondsRounded = self.calculateTime(start: launchStartTime, stop: launchEndTime)
            return CXMobileVitals(type: .cold, value: "\(millisecondsRounded)")
        }
        return nil
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxViewDidAppear, object: nil)
        
        self.anrDetector?.stopMonitoring()
        self.fpsTrigger.stopMonitoring()
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
                                                object: CXMobileVitals(type: .metricKit, value: metricPayloadJsonString))
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
