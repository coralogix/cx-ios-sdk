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
    var fpsDetector = FPSDetector()
    var metricsManagerClosure: (([String: Any]) -> Void)?
    var anrErrorClosure: ((String, String) -> Void)?
    
    // MARK: - Internal timer for periodic send
    private let sendInterval: TimeInterval = 15.0
    private var lastSendTime: Date?
    private var schedulingActive = false
                
    public func addMetricKitObservers() {
        MyMetricSubscriber.shared.metricKitClosure = { [weak self] dict in
            self?.metricsManagerClosure?(dict)
        }
        MyMetricSubscriber.shared.hangDiagnosticClosure = { [weak self] message, errorType in
            guard let self = self else { return }
            guard let anrErrorClosure = self.anrErrorClosure else {
                Log.d("[MetricsManager] Warning: anrErrorClosure not set, MetricKit hang not reported")
                return
            }
            anrErrorClosure(message, errorType)
        }
        MXMetricManager.shared.add(MyMetricSubscriber.shared)
    }
    
    public func removeObservers() {
        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
        self.stopAllDetectors()
        self.stopSendScheduler()
    }
    
    public func sendMobileVitals() {
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
        
        // Only include FPS if rendering detector is running
        if fpsDetector.isRunning {
            vitals[MobileVitalsType.fps.stringValue] = fpsDetector.statsDictionary()
        }
        
        // Don't send if no vitals collected
        guard !vitals.isEmpty else {
            Log.d("[MetricsManager] No vitals to send, skipping")
            return
        }
        
        // Send event
        self.metricsManagerClosure?(vitals)
        lastSendTime = Date()

        // Reset stats after sending
        cpuDetector?.reset()
        memoryDetector?.reset()
        slowFrozenFramesDetector?.reset()
        if fpsDetector.isRunning {
            fpsDetector.reset()
        }
    }
    
    func startMonitoring(using options: CoralogixExporterOptions?) {
        guard let options = options else { return }
        let hasEnabledVitals = self.initializeEnabledMobileVitals(using: options)
        
        // Only start scheduler if at least one mobile vital is enabled
        if hasEnabledVitals {
            startSendScheduler()
        }
    }
    
    private func initializeEnabledMobileVitals(using options: CoralogixExporterOptions) -> Bool {
        let mobileVitalsMap: [(CoralogixExporterOptions.MobileVitalsType, () -> Void)] = [
            (.coldDetector, self.startColdStartMonitoring),
            (.warmDetector, self.startWarmStartMonitoring),
            (.renderingDetector, self.fpsDetector.startMonitoring),
            (.cpuDetector, self.startCPUMonitoring),
            (.memoryDetector, self.startMemoryMonitoring),
            (.slowFrozenFramesDetector, self.startSlowFrozenFramesMonitoring)
        ]
        
        var anyEnabled = false
        for (type, initializer) in mobileVitalsMap where options.shouldInitMobileVitals(mobileVital: type) {
            initializer()
            anyEnabled = true
        }
        
        return anyEnabled
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
        self.anrDetector?.handleANRClosure = { [weak self] in
            self?.handleANREvent()
        }
        self.anrDetector?.startMonitoring()
    }
    
    private func handleANREvent() {
        let errorMessage = "Application Not Responding"
        let errorType = "ANR"
        
        // Report ANR as error (not mobile vitals)
        guard let anrErrorClosure = self.anrErrorClosure else {
            Log.d("[MetricsManager] Warning: anrErrorClosure not set, ANR event not reported")
            return
        }
        
        anrErrorClosure(errorMessage, errorType)
        Log.d("[MetricsManager] ANR error reported: \(errorMessage)")
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
        fpsDetector.stopMonitoring()
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
}
  
/// Abstracts `MXHangDiagnostic` so hang processing can be tested without
/// instantiating the uninitializable system class.
protocol HangDiagnosticProviding {
    var hangDurationMs: Double { get }
}

@available(iOS 14.0, *)
extension MXHangDiagnostic: HangDiagnosticProviding {
    var hangDurationMs: Double {
        hangDuration.converted(to: .milliseconds).value
    }
}

class MyMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = MyMetricSubscriber()
    var metricKitClosure: (([String: Any]) -> Void)?
    var hangDiagnosticClosure: ((String, String) -> Void)?

    // Handle received metrics
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let metricPayloadJsonString = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                let vital = [
                    Keys.metricKit.rawValue: [
                        Keys.name.rawValue: metricPayloadJsonString
                    ]
                ]
                self.metricKitClosure?(vital)
            }

            // TODO: Process application launch metrics (pending web UI support)
            // TODO: Process disk I/O metrics (pending web UI support)
            // TODO: Process memory metrics (pending web UI support)
        }
    }

    // Handle received diagnostics
    @available(iOS 14.0, *)
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            payload.hangDiagnostics?.forEach { processHang($0) }
        }
    }

    /// Processes a single hang diagnostic. Accepts `HangDiagnosticProviding` so tests
    /// can inject a mock without needing a real `MXHangDiagnostic` instance.
    func processHang(_ diagnostic: HangDiagnosticProviding) {
        let message = "App hang detected by MetricKit for \(Int(diagnostic.hangDurationMs.rounded())) ms"
        hangDiagnosticClosure?(message, "MXHangDiagnostic")
    }
}
