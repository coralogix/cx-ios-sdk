//
//  CoralogixCustomSpans.swift
//  Coralogix
//
//  Public Custom Spans API surface (parity with Coralogix Browser SDK).
//

import Foundation

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
        var builder = tracer.spanBuilder(spanName: name).setNoParent()
        if let labels {
            for (key, value) in labels {
                builder = builder.setAttribute(key: key, value: value)
            }
        }
        var otelSpan = builder.startSpan()
        rum.enrichCustomSpanMetadata(to: &otelSpan)
        return CoralogixGlobalSpan(span: otelSpan, tracer: tracer)
    }
}

/// A root custom span created via `CoralogixCustomTracer.startGlobalSpan(name:labels:)`.
public final class CoralogixGlobalSpan {
    public let span: any Span
    private let tracer: Tracer

    internal init(span: any Span, tracer: Tracer) {
        self.span = span
        self.tracer = tracer
    }

    /// Runs `work` with this span installed as the active span for OpenTelemetry context (e.g. outbound trace propagation).
    public func withContext<R>(_ work: () throws -> R) rethrows -> R {
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

    /// Starts a child span of this global span.
    public func startCustomSpan(name: String, labels: [String: String]? = nil) -> CoralogixCustomSpan {
        var builder = tracer.spanBuilder(spanName: name).setParent(span)
        if let labels {
            for (key, value) in labels {
                builder = builder.setAttribute(key: key, value: value)
            }
        }
        let child = builder.startSpan()
        return CoralogixCustomSpan(span: child)
    }

    /// Ends this span (`Span.end()`).
    public func endSpan() {
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
