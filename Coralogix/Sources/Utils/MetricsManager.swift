//
//  MetricsManager.swift
//
//
//  Created by Tomer Har Yoffi on 08/08/2024.
//

import Foundation
import MetricKit

@available(iOS 14.0, *)
class PerformanceMetricsManager: NSObject, MXMetricManagerSubscriber {
    override init() {
        super.init()
        MXMetricManager.shared.add(self)
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
    }
}
