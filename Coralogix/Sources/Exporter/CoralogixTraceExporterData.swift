//
//  CoralogixTraceExporterData.swift
//
//  Created by Coralogix Dev Team on 12/04/2026.
//
//  Data structure passed to the tracesExporter callback containing OTLP-formatted spans.

import Foundation

/// Data structure containing OTLP-formatted trace data for external export.
///
/// This struct is passed to the `tracesExporter` callback when configured in `CoralogixExporterOptions`.
/// It contains spans converted to OTLP JSON format, ready to be sent to an OTLP-compatible backend.
///
/// - Important: The callback is invoked on a background thread (BatchSpanProcessor's processing queue).
///   Do not block the callback with long-running operations.
public struct CoralogixTraceExporterData {
    /// The OTLP-formatted traces data containing resource spans grouped by resource and scope.
    public let tracesData: OtlpTracesData
    
    /// JSON-encoded representation of the traces data.
    /// Returns `nil` if encoding fails.
    public var jsonData: Data? {
        return SpanDataToOtlpConverter.toJSON(tracesData)
    }
    
    /// JSON string representation of the traces data.
    /// Returns `nil` if encoding fails.
    public var jsonString: String? {
        guard let data = jsonData else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// The number of spans included in this export batch.
    public var spanCount: Int {
        return tracesData.resourceSpans.reduce(0) { total, resourceSpan in
            total + resourceSpan.scopeSpans.reduce(0) { scopeTotal, scopeSpan in
                scopeTotal + scopeSpan.spans.count
            }
        }
    }
    
    internal init(tracesData: OtlpTracesData) {
        self.tracesData = tracesData
    }
    
    internal init(spans: [SpanData]) {
        self.tracesData = SpanDataToOtlpConverter.convert(spans: spans)
    }
}

/// Type alias for the traces exporter callback.
///
/// - Parameter data: The OTLP-formatted trace data ready for export.
///
/// - Important: This callback is invoked on a background thread (BatchSpanProcessor's processing queue).
///   Implementations must not block for extended periods. If you need to perform I/O operations,
///   dispatch them to another queue.
public typealias TracesExporterCallback = (CoralogixTraceExporterData) -> Void
