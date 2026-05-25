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
    var fpsDetector: FPSDetector?

    // MARK: - Reporting dependencies (CX-40573)
    //
    // Production wires `SpanMetricsCollector` / `SpanEventReporter`. When
    // unwired, calls into `emitMetricKitPayload` / `reportANR` /
    // `flushAll` drop with a `Log.d`. The wire format is pinned by
    // `WireFormatTests`. (Deprecated closure fallbacks removed in
    // CX-43341.)
    //
    // Threading: expected to be set once during init on the main thread.
    // Subsequent reads from background callbacks (MetricKit, ANR timer)
    // are unsynchronized; do not mutate after init. The `didSet` observers
    // below surface a `Log.e` if the invariant is violated — it can't be a
    // `precondition` because the SDK must never crash the host app
    // (see CLAUDE.md).
    var metricsCollector: MetricsCollector? {
        didSet {
            if oldValue != nil {
                Log.e("[MetricsManager] metricsCollector reassigned after init — this races background-thread reads (MetricKit/timer callbacks). Set once during init only.")
            }
        }
    }
    var eventReporter: EventReporter? {
        didSet {
            if oldValue != nil {
                Log.e("[MetricsManager] eventReporter reassigned after init — this races background-thread reads (ANR/MetricKit callbacks). Set once during init only.")
            }
        }
    }

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

    /// Emits a category-keyed dict (`{ "<category>": <payload> }`) — used
    /// by MetricKit and the cold/warm detectors — through the injected
    /// `MetricsCollector`. Wire format pinned by `WireFormatTests`.
    /// Drops with a debug log when no collector is wired (set in
    /// production by `CoralogixRum.setupCoreModules`).
    private func emitMetricKitPayload(_ dict: [String: Any]) {
        guard let metricsCollector = self.metricsCollector else {
            Log.d("[MetricsManager] no metricsCollector wired; dropping MetricKit/cold/warm payload with keys \(dict.keys.sorted())")
            return
        }
        // Pass the value through as-is: `VitalsMetric.payload` is typed
        // `Any` precisely so the dict / array shape produced by the
        // upstream producer reaches the collector unchanged.
        let metrics: [VitalsMetric] = dict.map { VitalsMetric(name: $0.key, payload: $0.value) }
        metricsCollector.collect(metrics)
    }

    /// Routes an ANR-shaped event through the injected `EventReporter`
    /// as a typed `ANRErrorEvent` (from CX-40572). Drops with a debug log
    /// when no reporter is wired (set in production by
    /// `CoralogixRum.initializeANRInstrumentation`).
    private func reportANR(message: String, errorType: String, source: String) {
        guard let eventReporter = self.eventReporter else {
            Log.d("[MetricsManager] Warning: no eventReporter set, \(source) not reported")
            return
        }
        eventReporter.report(ANRErrorEvent(errorMessage: message, errorType: errorType))
    }
    
    public func removeObservers() {
        MXMetricManager.shared.remove(MyMetricSubscriber.shared)
        self.stopAllDetectors()
        self.stopSendScheduler()
    }
    
    /// Fan-out: signal every periodic detector to push its current category
    /// through its own `metricsCollector` and reset. Replaces the previous
    /// pull-loop (`sendMobileVitals()` in CX-40573) — detectors now own
    /// their own emit per CX-43340.
    ///
    /// Each detector produces one `mobile_vitals` span via the production
    /// `SpanMetricsCollector` (one per category, instead of the pre-refactor
    /// single batched span). Wire format per span is unchanged — pinned by
    /// `WireFormatTests`.
    ///
    /// Called by the periodic scheduler (every 15s) and on view-change
    /// boundaries (`NavigationInstrumentation`). ANR is event-driven and
    /// pushes itself from `ANRDetector.handleANR()`; it does not participate
    /// in `flushAll`.
    public func flushAll() {
        cpuDetector?.flush()
        memoryDetector?.flush()
        slowFrozenFramesDetector?.flush()
        fpsDetector?.flush()
        // Match the pre-refactor invariant: bump lastSendTime only if at
        // least one detector would have contributed — otherwise an empty
        // scheduler tick (no detectors wired) would debounce subsequent
        // ticks for 15s. CPU/Memory/SlowFrozen contribute iff non-nil;
        // FPS contributes iff its display-link sampler is running.
        let anyContribution = cpuDetector != nil
            || memoryDetector != nil
            || slowFrozenFramesDetector != nil
            || (fpsDetector?.isRunning ?? false)
        if anyContribution {
            lastSendTime = Date()
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
            (.renderingDetector, self.startFPSMonitoring),
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
        self.anrDetector = ANRDetector(eventReporter: self.eventReporter)
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
        let detector = CPUDetector(metricsCollector: self.metricsCollector)
        detector.startMonitoring()
        self.cpuDetector = detector
    }

    func startMemoryMonitoring() {
        guard memoryDetector == nil else { return }
        let detector = MemoryDetector(metricsCollector: self.metricsCollector)
        detector.startMonitoring()
        self.memoryDetector = detector
    }

    func startSlowFrozenFramesMonitoring() {
        guard slowFrozenFramesDetector == nil else { return }
        let detector = SlowFrozenFramesDetector(metricsCollector: self.metricsCollector)
        detector.startMonitoring()
        self.slowFrozenFramesDetector = detector
    }

    func startFPSMonitoring() {
        guard fpsDetector == nil else { return }
        let detector = FPSDetector(metricsCollector: self.metricsCollector)
        detector.startMonitoring()
        self.fpsDetector = detector
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
        fpsDetector?.stopMonitoring()
        fpsDetector = nil
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
                        self.flushAll()
                    } else {
                        Log.d("[MetricsManager] Skipped send, only \(now.timeIntervalSince(last))s since last event")
                    }
                } else {
                    // First time we fire the scheduler
                    self.flushAll()
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
