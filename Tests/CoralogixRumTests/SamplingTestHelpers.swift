//
//  SamplingTestHelpers.swift
//
//  Shared helpers for the sampling-decoupling test surface (PIPEV2-3365). Used by
//  `LogSamplingDecouplingTests` (T4 — native path via `tracesExporter`) and
//  `HybridAPITests` T5 cases (hybrid path via `beforeSendCallBack`). Both paths
//  converge on the same per-span filter in `CoralogixExporter.export()`, so they
//  collect into the same `EventTypeCapture` shape.
//

import Foundation
import XCTest
import CoralogixInternal
@testable import Coralogix

/// Thread-safe append-only collector for `event_type` strings observed by either the
/// `tracesExporter` callback (raw OTLP shape) or the `beforeSendCallBack` (encoded CxSpan).
/// Both observation points sit below the per-span sampling filter in `CoralogixExporter.export()`,
/// so they yield the same set of strings — tests assert against `eventTypes` regardless of
/// which surface they wired.
final class EventTypeCapture {
    private let lock = NSLock()
    private var values: [String] = []

    /// Atomically appends a batch of event_type strings. Single lock acquisition per batch
    /// (not per element), so concurrent observers always see whole-batch boundaries — and
    /// the export hot path takes the lock at most once per `export()` call.
    func append(_ types: [String]) {
        guard !types.isEmpty else { return }
        lock.lock()
        values.append(contentsOf: types)
        lock.unlock()
    }

    var eventTypes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    /// Returns a closure suitable for `CoralogixExporterOptions.tracesExporter`. Walks the
    /// OTLP shape (resourceSpans → scopeSpans → spans) and pulls every `event_type` attribute.
    /// Captures `self` strongly so the test's local `let capture = …` only needs to outlive
    /// the test method (the rum/exporter retain the closure for the duration of export).
    func tracesExporterCallback() -> TracesExporterCallback {
        return { data in
            let types = data.tracesData.resourceSpans.flatMap { resourceSpan in
                resourceSpan.scopeSpans.flatMap { scopeSpan in
                    scopeSpan.spans.compactMap { span -> String? in
                        guard let kv = span.attributes.first(where: { $0.key == Keys.eventType.rawValue }) else {
                            return nil
                        }
                        if case .stringValue(let value) = kv.value { return value }
                        return nil
                    }
                }
            }
            self.append(types)
        }
    }

    /// Returns a closure suitable for `CoralogixExporterOptions.beforeSendCallBack`. Walks
    /// the encoded CxSpan dictionary (`text → cx_rum → event_context → type`) — the shape
    /// hybrid bridges (Flutter/RN) receive at the platform-channel boundary.
    func beforeSendCallback() -> ([[String: Any]]) -> Void {
        return { batch in
            self.append(batch.compactMap(Self.encodedEventType))
        }
    }

    private static func encodedEventType(in dict: [String: Any]) -> String? {
        guard let text = dict[Keys.text.rawValue] as? [String: Any],
              let cxRum = text[Keys.cxRum.rawValue] as? [String: Any],
              let eventContext = cxRum[Keys.eventContext.rawValue] as? [String: Any],
              let type = eventContext[Keys.type.rawValue] as? String else {
            return nil
        }
        return type
    }
}

/// Builds `CoralogixExporterOptions` for sampling tests. `beforeSendCallBack` is a `public var`
/// on the options (not an init parameter), so hybrid tests assign it post-init at the call site.
func makeSamplingOptions(sampleRate: Int,
                         exclude: Set<ExcludableInstrumentation>,
                         tracesExporter: TracesExporterCallback? = nil) -> CoralogixExporterOptions {
    return CoralogixExporterOptions(
        coralogixDomain: .US2,
        userContext: nil,
        environment: "test",
        application: "TestApp",
        version: "1.0.0",
        publicKey: "test-key",
        ignoreUrls: [],
        ignoreErrors: [],
        labels: nil,
        sessionSampleRate: sampleRate,
        excludeFromSampling: exclude,
        instrumentations: nil,
        tracesExporter: tracesExporter,
        debug: false
    )
}

/// Builds a `SpanData` that survives the encoding pipeline (`CxRumBuilder.build()` requires
/// session attributes) and carries the `event_type` under test. No `httpUrl`, no
/// `errorMessage`, so the URL and error filters in `export()` are no-ops.
func makeSamplingSpan(eventType: CoralogixEventType) -> SpanData {
    let attributes: [String: AttributeValue] = [
        Keys.eventType.rawValue: AttributeValue(eventType.rawValue),
        Keys.severity.rawValue: AttributeValue("3"),
        Keys.source.rawValue: AttributeValue("console"),
        Keys.environment.rawValue: AttributeValue("test"),
        Keys.userId.rawValue: AttributeValue("uid"),
        Keys.userName.rawValue: AttributeValue("Test User"),
        Keys.userEmail.rawValue: AttributeValue("test@example.com"),
        Keys.sessionId.rawValue: AttributeValue("session_001"),
        Keys.sessionCreationDate.rawValue: AttributeValue("1609459200")
    ]
    return SpanData(traceId: TraceId.random(),
                    spanId: SpanId.random(),
                    name: "testSpan_\(eventType.rawValue)",
                    kind: .client,
                    startTime: Date(),
                    attributes: attributes,
                    endTime: Date(),
                    hasEnded: true)
}

/// Test-only `SpanUploading` that returns `.success` without network I/O. Shared by all
/// sampling-decoupling tests so we don't keep duplicating per-file mocks.
final class SamplingMockSpanUploader: SpanUploading {
    func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
        return .success
    }
}
