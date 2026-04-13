//
//  OtlpModels.swift
//
//  Created by Coralogix Dev Team on 12/04/2026.
//
//  OTLP JSON format data models for traces export.
//  See: https://opentelemetry.io/docs/specs/otlp/#otlphttp-request

import Foundation

/// Root structure for OTLP traces export request.
/// Groups spans by resource and instrumentation scope.
public struct OtlpTracesData: Encodable {
    public let resourceSpans: [OtlpResourceSpans]
    
    enum CodingKeys: String, CodingKey {
        case resourceSpans = "resource_spans"
    }
}

/// A collection of spans from a resource.
public struct OtlpResourceSpans: Encodable {
    public let resource: OtlpResource
    public let scopeSpans: [OtlpScopeSpans]
    public let schemaUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case resource
        case scopeSpans = "scope_spans"
        case schemaUrl = "schema_url"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resource, forKey: .resource)
        try container.encode(scopeSpans, forKey: .scopeSpans)
        if let schemaUrl = schemaUrl, !schemaUrl.isEmpty {
            try container.encode(schemaUrl, forKey: .schemaUrl)
        }
    }
}

/// Resource information with attributes.
public struct OtlpResource: Encodable {
    public let attributes: [OtlpKeyValue]
}

/// A collection of spans from an instrumentation scope.
public struct OtlpScopeSpans: Encodable {
    public let scope: OtlpInstrumentationScope
    public let spans: [OtlpSpan]
    public let schemaUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case scope
        case spans
        case schemaUrl = "schema_url"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scope, forKey: .scope)
        try container.encode(spans, forKey: .spans)
        if let schemaUrl = schemaUrl, !schemaUrl.isEmpty {
            try container.encode(schemaUrl, forKey: .schemaUrl)
        }
    }
}

/// Instrumentation scope (library) information.
public struct OtlpInstrumentationScope: Encodable {
    public let name: String
    public let version: String?
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let version = version, !version.isEmpty {
            try container.encode(version, forKey: .version)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case version
    }
}

/// A span representing a trace segment.
public struct OtlpSpan: Encodable {
    public let traceId: String
    public let spanId: String
    public let parentSpanId: String?
    public let traceState: String?
    public let name: String
    public let kind: OtlpSpanKind
    public let startTimeUnixNano: String
    public let endTimeUnixNano: String
    public let attributes: [OtlpKeyValue]
    public let events: [OtlpSpanEvent]
    public let links: [OtlpSpanLink]
    public let status: OtlpStatus
    public let droppedAttributesCount: UInt32
    public let droppedEventsCount: UInt32
    public let droppedLinksCount: UInt32
    
    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case spanId = "span_id"
        case parentSpanId = "parent_span_id"
        case traceState = "trace_state"
        case name
        case kind
        case startTimeUnixNano = "start_time_unix_nano"
        case endTimeUnixNano = "end_time_unix_nano"
        case attributes
        case events
        case links
        case status
        case droppedAttributesCount = "dropped_attributes_count"
        case droppedEventsCount = "dropped_events_count"
        case droppedLinksCount = "dropped_links_count"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(traceId, forKey: .traceId)
        try container.encode(spanId, forKey: .spanId)
        if let parentSpanId = parentSpanId, !parentSpanId.isEmpty {
            try container.encode(parentSpanId, forKey: .parentSpanId)
        }
        if let traceState = traceState, !traceState.isEmpty {
            try container.encode(traceState, forKey: .traceState)
        }
        try container.encode(name, forKey: .name)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(startTimeUnixNano, forKey: .startTimeUnixNano)
        try container.encode(endTimeUnixNano, forKey: .endTimeUnixNano)
        if !attributes.isEmpty {
            try container.encode(attributes, forKey: .attributes)
        }
        if !events.isEmpty {
            try container.encode(events, forKey: .events)
        }
        if !links.isEmpty {
            try container.encode(links, forKey: .links)
        }
        try container.encode(status, forKey: .status)
        if droppedAttributesCount > 0 {
            try container.encode(droppedAttributesCount, forKey: .droppedAttributesCount)
        }
        if droppedEventsCount > 0 {
            try container.encode(droppedEventsCount, forKey: .droppedEventsCount)
        }
        if droppedLinksCount > 0 {
            try container.encode(droppedLinksCount, forKey: .droppedLinksCount)
        }
    }
}

/// OTLP span kind values as defined in the spec.
public enum OtlpSpanKind: String, Encodable {
    case unspecified = "SPAN_KIND_UNSPECIFIED"
    case `internal` = "SPAN_KIND_INTERNAL"
    case server = "SPAN_KIND_SERVER"
    case client = "SPAN_KIND_CLIENT"
    case producer = "SPAN_KIND_PRODUCER"
    case consumer = "SPAN_KIND_CONSUMER"
    
    public init(from spanKind: SpanKind) {
        switch spanKind {
        case .internal:
            self = .internal
        case .server:
            self = .server
        case .client:
            self = .client
        case .producer:
            self = .producer
        case .consumer:
            self = .consumer
        }
    }
}

/// Span event (timed annotation).
public struct OtlpSpanEvent: Encodable {
    public let timeUnixNano: String
    public let name: String
    public let attributes: [OtlpKeyValue]
    public let droppedAttributesCount: UInt32
    
    enum CodingKeys: String, CodingKey {
        case timeUnixNano = "time_unix_nano"
        case name
        case attributes
        case droppedAttributesCount = "dropped_attributes_count"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeUnixNano, forKey: .timeUnixNano)
        try container.encode(name, forKey: .name)
        if !attributes.isEmpty {
            try container.encode(attributes, forKey: .attributes)
        }
        if droppedAttributesCount > 0 {
            try container.encode(droppedAttributesCount, forKey: .droppedAttributesCount)
        }
    }
}

/// Span link to another span context.
public struct OtlpSpanLink: Encodable {
    public let traceId: String
    public let spanId: String
    public let traceState: String?
    public let attributes: [OtlpKeyValue]
    public let droppedAttributesCount: UInt32
    
    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case spanId = "span_id"
        case traceState = "trace_state"
        case attributes
        case droppedAttributesCount = "dropped_attributes_count"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(traceId, forKey: .traceId)
        try container.encode(spanId, forKey: .spanId)
        if let traceState = traceState, !traceState.isEmpty {
            try container.encode(traceState, forKey: .traceState)
        }
        if !attributes.isEmpty {
            try container.encode(attributes, forKey: .attributes)
        }
        if droppedAttributesCount > 0 {
            try container.encode(droppedAttributesCount, forKey: .droppedAttributesCount)
        }
    }
}

/// OTLP status with code and optional message.
public struct OtlpStatus: Encodable {
    public let code: OtlpStatusCode
    public let message: String?
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code.rawValue, forKey: .code)
        if let message = message, !message.isEmpty {
            try container.encode(message, forKey: .message)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

/// OTLP status codes as defined in the spec.
public enum OtlpStatusCode: String, Encodable {
    case unset = "STATUS_CODE_UNSET"
    case ok = "STATUS_CODE_OK"
    case error = "STATUS_CODE_ERROR"
    
    public init(from status: Status) {
        switch status {
        case .ok:
            self = .ok
        case .unset:
            self = .unset
        case .error:
            self = .error
        }
    }
}

/// Key-value pair for attributes using OTLP AnyValue structure.
public struct OtlpKeyValue: Encodable {
    public let key: String
    public let value: OtlpAnyValue
}

/// OTLP AnyValue that can hold different types.
public enum OtlpAnyValue: Encodable {
    case stringValue(String)
    case boolValue(Bool)
    case intValue(Int64)
    case doubleValue(Double)
    case arrayValue([OtlpAnyValue])
    case kvlistValue([OtlpKeyValue])
    
    enum CodingKeys: String, CodingKey {
        case stringValue = "string_value"
        case boolValue = "bool_value"
        case intValue = "int_value"
        case doubleValue = "double_value"
        case arrayValue = "array_value"
        case kvlistValue = "kvlist_value"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stringValue(let value):
            try container.encode(value, forKey: .stringValue)
        case .boolValue(let value):
            try container.encode(value, forKey: .boolValue)
        case .intValue(let value):
            try container.encode(String(value), forKey: .intValue)
        case .doubleValue(let value):
            try container.encode(value, forKey: .doubleValue)
        case .arrayValue(let values):
            try container.encode(ArrayWrapper(values: values), forKey: .arrayValue)
        case .kvlistValue(let values):
            try container.encode(KVListWrapper(values: values), forKey: .kvlistValue)
        }
    }
    
    public init(from attributeValue: AttributeValue) {
        switch attributeValue {
        case .string(let value):
            self = .stringValue(value)
        case .bool(let value):
            self = .boolValue(value)
        case .int(let value):
            self = .intValue(Int64(value))
        case .double(let value):
            self = .doubleValue(value)
        case .stringArray(let values):
            self = .arrayValue(values.map { .stringValue($0) })
        case .boolArray(let values):
            self = .arrayValue(values.map { .boolValue($0) })
        case .intArray(let values):
            self = .arrayValue(values.map { .intValue(Int64($0)) })
        case .doubleArray(let values):
            self = .arrayValue(values.map { .doubleValue($0) })
        case .set(let attributeSet):
            let kvPairs = attributeSet.labels
                .sorted { $0.key < $1.key }
                .map { key, value in
                    OtlpKeyValue(key: key, value: OtlpAnyValue(from: value))
                }
            self = .kvlistValue(kvPairs)
        }
    }
}

/// Wrapper for array values in OTLP format.
private struct ArrayWrapper: Encodable {
    let values: [OtlpAnyValue]
}

/// Wrapper for key-value list in OTLP format.
private struct KVListWrapper: Encodable {
    let values: [OtlpKeyValue]
}
