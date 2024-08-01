//
//  InstrumentationData.swift
//
//
//  Created by Coralogix Dev Team on 29/07/2024.
//

import Foundation

struct InstrumentationData {
    let otelSpan: OtelSpan
    let otelResource: OtelResource
 
    init(otel: SpanDataProtocol, labels: [String: Any]?) {
        self.otelSpan = OtelSpan(otel: otel, labels: labels)
        self.otelResource = OtelResource(otel: otel)
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.otelSpan.rawValue] = self.otelSpan.getDictionary()
        result[Keys.otelResource.rawValue] = self.otelResource.getDictionary()
        return result
    }
}

struct OtelSpan {
    let spanId: String
    let traceId: String
    let name: String
    let attributes: [String: Any]
    let startTime: [UInt64]
    let endTime: [UInt64]
    let status: [String: Any]
    let kind: Int
    let duration: [UInt64]
    
    init(otel: SpanDataProtocol, labels: [String: Any]?) {
        self.spanId = otel.getSpanId() ?? ""
        self.traceId = otel.getTraceId() ?? ""
        self.name = otel.getName() ?? ""
        var attributes = [String: Any]()
        
        if let otelAttributes = otel.getAttributes() {
            attributes = attributes.merging(otelAttributes) { (_, new) in new }
        }
        
        if let labels = labels {
            attributes = attributes.merging(labels) { (_, new) in new }
        }
        self.attributes = attributes
        let currentDate = Date().timeIntervalSince1970
        let defualtTime = [UInt64(currentDate), 0]
        if let startTime = otel.getStartTime() {
            self.startTime = startTime.openTelemetryFormat
        } else {
            self.startTime = defualtTime
        }
        
        if let endTime = otel.getEndTime() {
            self.endTime = endTime.openTelemetryFormat
        } else {
            self.endTime = defualtTime
        }
        
        self.status = otel.getStatusCode()
        self.kind = otel.getKind()
        if let startTime = otel.getStartTime(),
           let endTime = otel.getEndTime() {
            let delta = endTime - startTime
            self.duration = delta.openTelemetryFormat
        } else {
            self.duration = [0, 0]
        }
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.spanId.rawValue] = self.spanId
        result[Keys.traceId.rawValue] = self.traceId
        result[Keys.name.rawValue] = self.name
        result[Keys.attributes.rawValue] = self.attributes
        result[Keys.startTime.rawValue] = self.startTime
        result[Keys.endTime.rawValue] = self.endTime
        result[Keys.status.rawValue] = self.status
        result[Keys.kind.rawValue] = self.kind
        result[Keys.duration.rawValue] = self.duration
        return result
    }
}

struct OtelResource {
    let attributes: [String: Any]
    
    init(otel: SpanDataProtocol) {
        self.attributes = otel.getResources()
    }
    
    func getDictionary() -> [String: Any] {
        return [Keys.attributes.rawValue: self.attributes]
    }
}
