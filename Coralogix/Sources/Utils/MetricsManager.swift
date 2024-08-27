//
//  MetricsManager.swift
//
//
//  Created by Tomer Har Yoffi on 08/08/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import MetricKit

@available(iOS 14.0, *)
class PerformanceMetricsManager: NSObject, MXMetricManagerSubscriber {
    var launchStartTime: CFAbsoluteTime?
    var launchEndTime: CFAbsoluteTime?
    var foregroundStartTime: CFAbsoluteTime?
    var foregroundEndTime: CFAbsoluteTime?
    var anrDetector: CXANRDetector?
    
    override init() {
        super.init()
        MXMetricManager.shared.add(self)
        self.anrDetector = CXANRDetector()
        self.anrDetector?.startMonitoring()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleNotification(notification:)),
                                               name: .cxRumNotificationMetrics,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminateNotification),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
    }
    
    @objc private func applicationDidEnterBackground() {
        Log.d("App did enter Background")
        self.foregroundStartTime = CFAbsoluteTimeGetCurrent()
        self.foregroundEndTime = nil
    }
    
    @objc private func appWillEnterForeground() {
        Log.d("App did enter Foreground")
         if let foregroundStartTime = foregroundStartTime,
                  self.foregroundEndTime == nil {
             let currentTime = CFAbsoluteTimeGetCurrent()
            self.foregroundEndTime = currentTime
            let warmStartDuration = currentTime - foregroundStartTime
            Log.d("Warm start duration: \(warmStartDuration) seconds")
        }
    }
    
    @objc private func appWillTerminateNotification() {
        Log.d("App will Terminate Notification")
        self.anrDetector?.stopMonitoring()
    }
    
    func coldStart() {
        launchStartTime = CFAbsoluteTimeGetCurrent()
    }
    
    @objc func handleNotification(notification: Notification) {
        if let metrics = notification.object as? [String: Any] {
            if let launchStartTime = self.launchStartTime,
               let launchEndTime = metrics[Keys.coldEnd.rawValue] as? CFAbsoluteTime,
               self.launchEndTime == nil {
                self.launchEndTime = launchEndTime
                let coldStartDuration = launchEndTime - launchStartTime
                Log.d("Cold start duration: \(coldStartDuration) seconds")
            }
        }
    }
    
    func coldStop() {
        if let launchStartTime = self.launchStartTime {
            let launchEndTime = CFAbsoluteTimeGetCurrent()
            let coldStartDuration = launchEndTime - launchStartTime
            Log.d("Cold start duration: \(coldStartDuration) seconds")
        }
    }
    
    // Handle received metrics
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            
            if let metricPayloadJsonString = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                Log.d("metricPayloadJsonString  \(metricPayloadJsonString)")
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
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let hangDiagnostics = payload.hangDiagnostics {
                for hangDiagnostic in hangDiagnostics {
                    Log.d("Call Stack Tree: \(hangDiagnostic.callStackTree)")
                }
            }
        }
    }
    
    deinit {
        MXMetricManager.shared.remove(self)
        NotificationCenter().removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter().removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter().removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter().removeObserver(self, name: .cxRumNotificationMetrics, object: nil)
    }
}
