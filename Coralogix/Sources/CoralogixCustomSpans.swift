//
//  CoralogixCustomSpans.swift
//  Coralogix
//
//  Public Custom Spans API surface (parity with Coralogix Browser SDK).
//

import Foundation
import CoralogixInternal

// MARK: - Global span registry (CX-35952, Browser `window.__globalSpan__` equivalent)

/// Process-wide active custom global span and the OTel context to restore after `endSpan()`.
final class CoralogixCustomGlobalSpanRegistry {
    static let shared = CoralogixCustomGlobalSpanRegistry()

    private let lock = NSLock()
    private weak var registeredGlobal: (any Span)?
    private weak var spanActiveBeforeGlobal: (any Span)?

    private init() {}

    /// Ends the span and re-activates the OTel context from before `startGlobalSpan()` (single implementation for `endSpan` / `shutdown` / tests).
    private static func endGlobalSpanAndRestorePrevious(_ span: any Span, previous: (any Span)?) {
        span.end()
        if let previous {
            OpenTelemetry.instance.contextProvider.setActiveSpan(previous)
        }
    }

    /// Returns `false` if a global custom span is already registered (second `startGlobalSpan` is ignored, like the Browser SDK).
    func registerGlobalSpan(_ span: any Span) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if registeredGlobal != nil {
            return false
        }
        spanActiveBeforeGlobal = OpenTelemetry.instance.contextProvider.activeSpan
        registeredGlobal = span
        OpenTelemetry.instance.contextProvider.setActiveSpan(span)
        return true
    }

    /// Ends the registry entry for this span: clears state, ends the span, restores previous active context. Returns `false` if `span` is not the registered global.
    func endGlobalSpanIfMatches(_ span: any Span) -> Bool {
        lock.lock()
        let isMatch = (registeredGlobal as AnyObject?) === (span as AnyObject)
        let previous = spanActiveBeforeGlobal
        if isMatch {
            registeredGlobal = nil
            spanActiveBeforeGlobal = nil
        }
        lock.unlock()
        guard isMatch else {
            return false
        }
        Self.endGlobalSpanAndRestorePrevious(span, previous: previous)
        return true
    }

    /// Clears any registered global custom span (`shutdown` and unit tests). Ends the span if still active and restores the pre-global OTel context.
    internal func teardownIfNeeded() {
        lock.lock()
        let g = registeredGlobal
        let previous = spanActiveBeforeGlobal
        registeredGlobal = nil
        spanActiveBeforeGlobal = nil
        lock.unlock()
        guard let g else { return }
        Self.endGlobalSpanAndRestorePrevious(g, previous: previous)
    }
}

/// Browser SDK sets `EVENT_TYPE` to `custom-span` on global and nested custom spans (`coralogix-rum.ts`).
private func stampCoralogixCustomSpanRUM(on span: inout any Span) {
    span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.customSpan.rawValue)
    span.setAttribute(key: Keys.source.rawValue, value: Keys.code.rawValue)
    span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
}

// MARK: - Custom span labels (CX-35953, Browser `getCustomMergedLabels` / `setCustomLabelsForSpan`)

/// Merge order: `base` (SDK-level `[String: Any]`) then `layer` (`[String: String]` wins on key collision).
private func mergingCustomLabelLayer(into base: [String: Any], _ layer: [String: String]?) -> [String: Any] {
    guard let layer, !layer.isEmpty else { return base }
    var out = base
    for (key, value) in layer {
        out[key] = value
    }
    return out
}

/// Writes Browser-parity `custom_labels` JSON on the span for RUM (`Helper.getLabels` / Explorer).
private func setMergedCustomLabelsJSON(merged: [String: Any], on span: inout any Span) {
    guard !merged.isEmpty else { return }
    let json = Helper.convertDictionayToJsonString(dict: merged)
    guard !json.isEmpty else {
        Log.w("Custom span labels could not be JSON-encoded — custom_labels attribute omitted")
        return
    }
    span.setAttribute(key: Keys.customLabels.rawValue, value: json)
}

/// Auto-instrumentation categories that may be excluded from custom-tracer context behavior in future releases.
public enum CoralogixIgnoredInstrument: Hashable {
    case networkRequests
    case userInteractions
    case errors
}

/// Tracer for manual global and nested custom spans (`getCustomTracer(ignoredInstruments:)` on `CoralogixRum`).
public final class CoralogixCustomTracer {
    internal weak var rum: CoralogixRum?

    /// Instruments passed at creation; reserved for future propagation and instrumentation filtering.
    public let ignoredInstruments: Set<CoralogixIgnoredInstrument>

    internal init(rum: CoralogixRum, ignoredInstruments: Set<CoralogixIgnoredInstrument>) {
        self.rum = rum
        self.ignoredInstruments = ignoredInstruments
    }

    /// Starts a new root span (new trace). Returns `nil` if the SDK is not initialized or the `CoralogixRum` instance was deallocated.
    public func startGlobalSpan(name: String, labels: [String: String]? = nil) -> CoralogixGlobalSpan? {
        guard let rum = rum, rum.isInitialized else {
            return nil
        }
        let tracer = rum.tracerProvider()
        let sdkLabels = rum.labels ?? [:]
        let mergedSdkAndGlobal = mergingCustomLabelLayer(into: sdkLabels, labels)
        var otelSpan = tracer.spanBuilder(spanName: name).setNoParent().startSpan()
        stampCoralogixCustomSpanRUM(on: &otelSpan)
        rum.addRumCorrelationMetadata(to: &otelSpan)
        setMergedCustomLabelsJSON(merged: mergedSdkAndGlobal, on: &otelSpan)
        guard CoralogixCustomGlobalSpanRegistry.shared.registerGlobalSpan(otelSpan) else {
            Log.w("Global custom span already active — startGlobalSpan ignored; ending orphan span")
            otelSpan.end()
            return nil
        }
        return CoralogixGlobalSpan(
            span: otelSpan,
            tracer: tracer,
            rum: rum,
            mergedSdkAndGlobalLabels: mergedSdkAndGlobal
        )
    }
}

/// A root custom span created via `CoralogixCustomTracer.startGlobalSpan(name:labels:)`.
public final class CoralogixGlobalSpan {
    public let span: any Span
    private let tracer: Tracer
    private weak var rum: CoralogixRum?
    /// Snapshot of SDK ∪ global labels at `startGlobalSpan` time; child spans merge child keys on top (CX-35953).
    private let mergedSdkAndGlobalLabels: [String: Any]

    internal init(
        span: any Span,
        tracer: Tracer,
        rum: CoralogixRum,
        mergedSdkAndGlobalLabels: [String: Any]
    ) {
        self.span = span
        self.tracer = tracer
        self.rum = rum
        self.mergedSdkAndGlobalLabels = mergedSdkAndGlobalLabels
    }

    private func isRegisteredGlobalActiveInOTel() -> Bool {
        let active = OpenTelemetry.instance.contextProvider.activeSpan
        return (active as AnyObject?) === (span as AnyObject)
    }

    /// Runs `work` with this span as the active OTel context. If it is already active (after `startGlobalSpan`), runs `work` without removing it from context.
    public func withContext<R>(_ work: () throws -> R) rethrows -> R {
        if isRegisteredGlobalActiveInOTel() {
            return try work()
        }
        let previous = OpenTelemetry.instance.contextProvider.activeSpan
        OpenTelemetry.instance.contextProvider.setActiveSpan(span)
        defer {
            OpenTelemetry.instance.contextProvider.removeContextForSpan(span)
            if let previous {
                OpenTelemetry.instance.contextProvider.setActiveSpan(previous)
            }
        }
        return try work()
    }

    /// Starts a child span while the global span is the OTel active span (same trace/parent as Browser `context.with(global, …)`).
    public func startCustomSpan(name: String, labels: [String: String]? = nil) -> CoralogixCustomSpan {
        let baseBuilder: any SpanBuilder
        if isRegisteredGlobalActiveInOTel() {
            baseBuilder = tracer.spanBuilder(spanName: name)
        } else {
            Log.w("startCustomSpan: global span is not active; using explicit parent — prefer calling before endSpan()")
            baseBuilder = tracer.spanBuilder(spanName: name).setParent(span)
        }
        let mergedAllLevels = mergingCustomLabelLayer(into: mergedSdkAndGlobalLabels, labels)
        var child = baseBuilder.startSpan()
        stampCoralogixCustomSpanRUM(on: &child)
        rum?.addRumCorrelationMetadata(to: &child)
        setMergedCustomLabelsJSON(merged: mergedAllLevels, on: &child)
        return CoralogixCustomSpan(span: child)
    }

    /// Ends this global span and restores the OTel active context from before `startGlobalSpan()`.
    public func endSpan() {
        if CoralogixCustomGlobalSpanRegistry.shared.endGlobalSpanIfMatches(span) {
            return
        }
        Log.w("endSpan() on global span that was not registered; ending span without registry restore")
        span.end()
    }
}

/// A nested custom span created via `CoralogixGlobalSpan.startCustomSpan(name:labels:)`.
public final class CoralogixCustomSpan {
    public let span: any Span

    internal init(span: any Span) {
        self.span = span
    }

    public func endSpan() {
        span.end()
    }

    public func setAttribute(key: String, value: String) {
        span.setAttribute(key: key, value: value)
    }

    public func setAttribute(key: String, value: Int) {
        span.setAttribute(key: key, value: value)
    }

    public func setAttribute(key: String, value: Double) {
        span.setAttribute(key: key, value: value)
    }

    public func setAttribute(key: String, value: Bool) {
        span.setAttribute(key: key, value: value)
    }

    public func setAttribute(key: String, value: AttributeValue?) {
        span.setAttribute(key: key, value: value)
    }

    public func addEvent(name: String) {
        span.addEvent(name: name)
    }

    public func addEvent(name: String, timestamp: Date) {
        span.addEvent(name: name, timestamp: timestamp)
    }

    public func addEvent(name: String, attributes: [String: AttributeValue]) {
        span.addEvent(name: name, attributes: attributes)
    }

    public func addEvent(name: String, attributes: [String: AttributeValue], timestamp: Date) {
        span.addEvent(name: name, attributes: attributes, timestamp: timestamp)
    }

    public func setStatus(_ status: Status) {
        span.status = status
    }
}
