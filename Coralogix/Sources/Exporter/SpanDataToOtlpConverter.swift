//
//  SpanDataToOtlpConverter.swift
//
//  Created by Coralogix Dev Team on 12/04/2026.
//
//  Converts OpenTelemetry SpanData objects into OTLP JSON format.
//  Implements the core serialization logic for the traces exporter.
//
//  Conversion rules:
//  - traceId: SpanData.traceId → Base64 encoded 16 bytes
//  - spanId: SpanData.spanId → Base64 encoded 8 bytes
//  - startTimeUnixNano / endTimeUnixNano: Date → UInt64(timeIntervalSince1970 * 1_000_000_000) as String
//  - attributes: [String: AttributeValue] → [OtlpKeyValue]
//  - status: Status → OtlpStatus (OK → STATUS_CODE_OK, ERROR → STATUS_CODE_ERROR, UNSET → STATUS_CODE_UNSET)
//  - kind: SpanKind → SPAN_KIND_* string
//
//  Spans are grouped by resource into resource_spans, then by instrumentation scope into scope_spans.

import Foundation
import CoralogixInternal

/// Converts SpanData to OTLP JSON format.
struct SpanDataToOtlpConverter {
    
    /// Converts an array of SpanData to OTLP traces format, grouped by resource and scope.
    /// - Parameter spans: Array of SpanData to convert
    /// - Returns: OtlpTracesData containing all spans grouped appropriately
    static func convert(spans: [SpanData]) -> OtlpTracesData {
        let groupedByResource = groupSpansByResource(spans: spans)
        
        let resourceSpans = groupedByResource.map { resourceKey, resourceSpans -> OtlpResourceSpans in
            let groupedByScope = groupSpansByScope(spans: resourceSpans)
            
            let scopeSpans = groupedByScope.map { scopeKey, scopedSpans -> OtlpScopeSpans in
                let otlpSpans = scopedSpans.map { convertSpan($0) }
                let scope = scopedSpans.first?.instrumentationScope ?? InstrumentationScopeInfo()
                
                return OtlpScopeSpans(
                    scope: OtlpInstrumentationScope(
                        name: scope.name,
                        version: scope.version
                    ),
                    spans: otlpSpans,
                    schemaUrl: scope.schemaUrl
                )
            }
            
            let resource = resourceSpans.first?.resource ?? Resource()
            
            return OtlpResourceSpans(
                resource: convertResource(resource),
                scopeSpans: Array(scopeSpans),
                schemaUrl: nil
            )
        }
        
        return OtlpTracesData(resourceSpans: Array(resourceSpans))
    }
    
    /// Converts OtlpTracesData to JSON Data.
    /// - Parameter tracesData: The OTLP traces data to encode
    /// - Returns: JSON encoded Data, or nil if encoding fails
    static func toJSON(_ tracesData: OtlpTracesData) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        
        do {
            return try encoder.encode(tracesData)
        } catch {
            Log.e("Failed to encode OTLP traces data: \(error)")
            return nil
        }
    }
    
    /// Convenience method to convert spans directly to JSON Data.
    /// - Parameter spans: Array of SpanData to convert
    /// - Returns: JSON encoded Data, or nil if encoding fails
    static func toJSON(spans: [SpanData]) -> Data? {
        let tracesData = convert(spans: spans)
        return toJSON(tracesData)
    }
    
    // MARK: - Private Conversion Methods
    
    private static func convertSpan(_ span: SpanData) -> OtlpSpan {
        let statusMessage: String?
        if case .error(let description) = span.status {
            statusMessage = description
        } else {
            statusMessage = nil
        }
        
        return OtlpSpan(
            traceId: encodeTraceIdToBase64(span.traceId),
            spanId: encodeSpanIdToBase64(span.spanId),
            parentSpanId: span.parentSpanId.map { encodeSpanIdToBase64($0) },
            traceState: span.traceState.entries.isEmpty ? nil : traceStateToString(span.traceState),
            name: span.name,
            kind: OtlpSpanKind(from: span.kind),
            startTimeUnixNano: dateToUnixNanoString(span.startTime),
            endTimeUnixNano: dateToUnixNanoString(span.endTime),
            attributes: convertAttributes(span.attributes),
            events: span.events.map { convertEvent($0) },
            links: span.links.map { convertLink($0) },
            status: OtlpStatus(
                code: OtlpStatusCode(from: span.status),
                message: statusMessage
            ),
            droppedAttributesCount: UInt32(max(0, span.totalAttributeCount - span.attributes.count)),
            droppedEventsCount: UInt32(max(0, span.totalRecordedEvents - span.events.count)),
            droppedLinksCount: UInt32(max(0, span.totalRecordedLinks - span.links.count))
        )
    }
    
    private static func convertResource(_ resource: Resource) -> OtlpResource {
        return OtlpResource(attributes: convertAttributes(resource.attributes))
    }
    
    private static func convertEvent(_ event: SpanData.Event) -> OtlpSpanEvent {
        return OtlpSpanEvent(
            timeUnixNano: dateToUnixNanoString(event.timestamp),
            name: event.name,
            attributes: convertAttributes(event.attributes),
            droppedAttributesCount: 0
        )
    }
    
    private static func convertLink(_ link: SpanData.Link) -> OtlpSpanLink {
        return OtlpSpanLink(
            traceId: encodeTraceIdToBase64(link.context.traceId),
            spanId: encodeSpanIdToBase64(link.context.spanId),
            traceState: link.context.traceState.entries.isEmpty ? nil : traceStateToString(link.context.traceState),
            attributes: convertAttributes(link.attributes),
            droppedAttributesCount: 0
        )
    }
    
    private static func convertAttributes(_ attributes: [String: AttributeValue]) -> [OtlpKeyValue] {
        return attributes.map { key, value in
            OtlpKeyValue(key: key, value: OtlpAnyValue(from: value))
        }
    }
    
    // MARK: - Base64 Encoding
    
    /// Encodes a TraceId (16 bytes) to Base64 string.
    /// TraceId is stored as two UInt64 values (idHi, idLo) in big-endian order.
    static func encodeTraceIdToBase64(_ traceId: TraceId) -> String {
        var bytes = [UInt8](repeating: 0, count: TraceId.size)
        traceId.copyBytesTo(dest: &bytes, destOffset: 0)
        return Data(bytes).base64EncodedString()
    }
    
    /// Encodes a SpanId (8 bytes) to Base64 string.
    /// SpanId is stored as a single UInt64 in big-endian order.
    static func encodeSpanIdToBase64(_ spanId: SpanId) -> String {
        var bytes = [UInt8](repeating: 0, count: SpanId.size)
        spanId.copyBytesTo(dest: &bytes, destOffset: 0)
        return Data(bytes).base64EncodedString()
    }
    
    // MARK: - Time Conversion
    
    /// Converts a Date to Unix nanoseconds as a String.
    /// OTLP requires timestamps as strings to preserve precision.
    static func dateToUnixNanoString(_ date: Date) -> String {
        let nanos = UInt64(date.timeIntervalSince1970 * 1_000_000_000)
        return String(nanos)
    }
    
    // MARK: - TraceState Conversion
    
    private static func traceStateToString(_ traceState: TraceState) -> String {
        return traceState.entries
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }
    
    // MARK: - Grouping Logic
    
    /// Groups spans by their resource, using service name as the primary key.
    private static func groupSpansByResource(spans: [SpanData]) -> [String: [SpanData]] {
        var grouped = [String: [SpanData]]()
        
        for span in spans {
            let key = resourceKey(for: span.resource)
            grouped[key, default: []].append(span)
        }
        
        return grouped
    }
    
    /// Groups spans by their instrumentation scope.
    private static func groupSpansByScope(spans: [SpanData]) -> [String: [SpanData]] {
        var grouped = [String: [SpanData]]()
        
        for span in spans {
            let key = scopeKey(for: span.instrumentationScope)
            grouped[key, default: []].append(span)
        }
        
        return grouped
    }
    
    /// Creates a unique key for a resource based on its attributes.
    private static func resourceKey(for resource: Resource) -> String {
        let serviceName = resource.attributes[ResourceAttributes.serviceName.rawValue]?.description ?? "unknown"
        let sortedAttrs = resource.attributes
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.description)" }
            .joined(separator: ",")
        return "\(serviceName)|\(sortedAttrs)"
    }
    
    /// Creates a unique key for an instrumentation scope.
    private static func scopeKey(for scope: InstrumentationScopeInfo) -> String {
        return "\(scope.name)|\(scope.version ?? "")"
    }
}
