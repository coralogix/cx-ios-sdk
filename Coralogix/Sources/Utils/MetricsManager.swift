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

public class CXMetricsManager: NSObject { /*}, MXMetricManagerSubscriber { */
    var launchStartTime: CFAbsoluteTime?
    var launchEndTime: CFAbsoluteTime?
    var foregroundStartTime: CFAbsoluteTime?
    var foregroundEndTime: CFAbsoluteTime?
    var cxAnrDetector: CXANRDetector?
    let cxFPSTrigger = CXFPSTrigger()
    let mobileVitalsFPSSamplingRate = 60
    
    override init() {
        super.init()
        // MXMetricManager.shared.add(self)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.handleNotification(notification:)),
                                               name: .cxRumNotificationMetrics,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.applicationDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.appWillTerminateNotification),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
    }
    
    func startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: Int) {
        self.cxFPSTrigger.startMonitoring(xTimesPerHour: mobileVitalsFPSSamplingRate)
    }
    
    @objc internal func applicationDidEnterBackground() {
        Log.d("App did enter Background")
        self.foregroundStartTime = CFAbsoluteTimeGetCurrent()
        self.foregroundEndTime = nil
        self.cxFPSTrigger.stopMonitoring()
    }
    
    @objc internal func appWillEnterForeground() {
        Log.d("App did enter Foreground")
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
        self.startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: self.mobileVitalsFPSSamplingRate)
    }
    
    @objc internal func appWillTerminateNotification() {
        Log.d("App will Terminate Notification")
        self.cxAnrDetector?.stopMonitoring()
        self.cxAnrDetector = nil
    }
    
    func startColdStartMonitoring() {
        self.launchStartTime = CFAbsoluteTimeGetCurrent()
    }
    
    func startANRMonitoring() {
        self.cxAnrDetector = CXANRDetector()
        self.cxAnrDetector?.startMonitoring()
    }
    
    @objc func handleNotification(notification: Notification) {
        if let metrics = notification.object as? [String: Any] {
            if let launchStartTime = self.launchStartTime,
               let launchEndTime = metrics[Keys.coldEnd.rawValue] as? CFAbsoluteTime,
               self.launchEndTime == nil {
                self.launchEndTime = launchEndTime
                let coldStartDurationInSeconds = launchEndTime - launchStartTime
                let coldStartDurationInMilliseconds = coldStartDurationInSeconds * 1000
                
                // Convert to an integer if you want to remove the decimal part
                let millisecondsRounded = Int(coldStartDurationInMilliseconds)

                Log.d("[Metric] Cold start duration: \(millisecondsRounded) milliseconds")
                
                // send instrumentaion event
                NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                                object: CXMobileVitals(type: .cold, value: "\(millisecondsRounded)"))
            }
        }
    }
    
//    // Handle received metrics
//    public func didReceive(_ payloads: [MXMetricPayload]) {
//        for payload in payloads {
//            
//            if let metricPayloadJsonString = String(data: payload.jsonRepresentation(), encoding: .utf8) {
//                Log.d("metricPayloadJsonString  \(metricPayloadJsonString)")
//            }
//                    
//            if let applicationLaunchMetric = payload.applicationLaunchMetrics {
//                Log.d("Launch Time: \(applicationLaunchMetric.histogrammedApplicationResumeTime)")
//                Log.d("Time to First Draw: \(applicationLaunchMetric.histogrammedTimeToFirstDraw)")
//            }
//            
//            if let diskWritesMetric = payload.diskIOMetrics {
//                Log.d("Disk Writes: \(diskWritesMetric.cumulativeLogicalWrites)")
//            }
//            
//            if let memoryMetric = payload.memoryMetrics {
//                Log.d("Memory Usage: \(memoryMetric.averageSuspendedMemory)")
//            }
//        }
//    }
//    
//    // Handle received diagnostics
//    @available(iOS 14.0, *)
//    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
//        for payload in payloads {
//            if let hangDiagnostics = payload.hangDiagnostics {
//                for hangDiagnostic in hangDiagnostics {
//                    Log.d("Call Stack Tree: \(hangDiagnostic.callStackTree)")
//                }
//            }
//        }
//    }
    
    deinit {
//        MXMetricManager.shared.remove(self)
        NotificationCenter().removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter().removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter().removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter().removeObserver(self, name: .cxRumNotificationMetrics, object: nil)
        self.cxAnrDetector?.stopMonitoring()
        self.cxFPSTrigger.stopMonitoring()
    }
}
