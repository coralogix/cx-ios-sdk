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

    // MARK: - Reporting dependencies (CX-40573)
    //
    // When set, these protocol-typed sinks take precedence over the legacy
    // closure properties below. Production wires `SpanMetricsCollector` /
    // `SpanEventReporter`; the wire format produced by either path is
    // byte-identical to the dict the deprecated closures emit — pinned by
    // `WireFormatTests`.
    //
    // Threading: expected to be set once during init on the main thread.
    // Subsequent reads from background callbacks (MetricKit, ANR timer)
    // are unsynchronized; do not mutate after init.
    var metricsCollector: MetricsCollector?
    var eventReporter: EventReporter?

    // MARK: - Legacy closure fallbacks (deprecated)
    @available(*, deprecated, message: "Inject a MetricsCollector via the new metricsCollector property instead. Closure-based wiring will be removed in a future major release.")
    var metricsManagerClosure: (([String: Any]) -> Void)?
    @available(*, deprecated, message: "Inject an EventReporter via the new eventReporter property instead. Closure-based wiring will be removed in a future major release.")
    var anrErrorClosure: ((String, String) -> Void)?

    // MARK: - Internal timer for periodic send
    private let sendInterval: TimeInterval = 15.0
    private var lastSendTime: Date?
    private var schedulingActive = false
                
    public func addMetricKitObservers() {
        MyMetricSubscriber.shared.metricKitClosure = { [weak self] dict in
            self?.emitMetricKitPayload(dict)
        }
        MyMetricSubscriber.shared.hangDiagnosticClosure = { [weak self] message, errorType in
            guard let self = self else { return }
            self.reportANR(message: message, errorType: errorType, source: "MetricKit hang")
        }
        MXMetricManager.shared.add(MyMetricSubscriber.shared)
    }

    /// Re-emits a category-keyed dict (`{ "<category>": <payload> }`) — used
    /// by MetricKit and the cold/warm detectors — through whichever sink is
    /// wired, preferring the protocol path. The shape sent on the wire is
    /// byte-identical either way (pinned by `WireFormatTests`).
    private func emitMetricKitPayload(_ dict: [String: Any]) {
        if let metricsCollector = self.metricsCollector {
            // Pass the value through as-is: `VitalsMetric.payload` is typed
            // `Any` precisely so the dict / array shape produced by the
            // upstream producer reaches the collector unchanged.
            let metrics: [VitalsMetric] = dict.map { VitalsMetric(name: $0.key, payload: $0.value) }
            metricsCollector.collect(metrics)
            return
        }
        self.metricsManagerClosure?(dict)
    }

    /// Routes an ANR-shaped event through whichever sink is wired. Uses the
    /// typed `ANRErrorEvent` (from CX-40572) when going through the protocol;
    /// falls back to the deprecated closure otherwise.
    private func reportANR(message: String, errorType: String, source: String) {
        if let eventReporter = self.eventReporter {
            eventReporter.report(ANRErrorEvent(errorMessage: message, errorType: errorType))
            return
        }
        guard let anrErrorClosure = self.anrErrorClosure else {
            Log.d("[MetricsManager] Warning: no eventReporter or anrErrorClosure set, \(source) not reported")
            return
        }
        anrErrorClosure(message, errorType)
    }
    
    public func removeObservers() {
        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
        self.stopAllDetectors()
        self.stopSendScheduler()
    }
    
    public func sendMobileVitals() {
        // Build a [VitalsMetric] in the same category order used by the
        // legacy dict path. The dict and the protocol path are equivalent —
        // see `WireFormatTests.testMetricsManager_sendMobileVitals_*`.
        var metrics: [VitalsMetric] = []
        if let cpuDetector = cpuDetector {
            metrics.append(VitalsMetric(name: Keys.cpu.rawValue, payload: cpuDetector.statsDictionary()))
        }
        if let memoryDetector = memoryDetector {
            metrics.append(VitalsMetric(name: Keys.memory.rawValue, payload: memoryDetector.statsDictionary()))
        }
        if let slowFrozenFramesDetector = slowFrozenFramesDetector {
            metrics.append(VitalsMetric(name: Keys.slowFrozen.rawValue, payload: slowFrozenFramesDetector.statsDictionary()))
        }
        if fpsDetector.isRunning {
            metrics.append(VitalsMetric(name: MobileVitalsType.fps.stringValue, payload: fpsDetector.statsDictionary()))
        }

        guard !metrics.isEmpty else {
            Log.d("[MetricsManager] No vitals to send, skipping")
            return
        }

        if let metricsCollector = self.metricsCollector {
            metricsCollector.collect(metrics)
        } else {
            // Legacy closure path — reconstruct the same dict shape callers
            // have always received. Inlined so the fallback doesn't require
            // a separate `MetricsCollector` impl; `WireFormatTests` pins
            // this reconstruction to be byte-identical to
            // `[VitalsMetric].toDictionary()`.
            self.metricsManagerClosure?(metrics.toDictionary())
        }
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
            self?.emitMetricKitPayload(dict)
        }
        detector.startMonitoring()
        self.coldDetector = detector
    }

    func startWarmStartMonitoring() {
        guard warmDetector == nil else { return }
        let detector = WarmDetector()
        detector.handleWarmClosure = { [weak self] dict in
            self?.emitMetricKitPayload(dict)
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
        let errorMessage = WireValues.anrErrorMessage.rawValue
        let errorType = WireValues.anrErrorType.rawValue
        reportANR(message: errorMessage, errorType: errorType, source: "ANR event")
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
