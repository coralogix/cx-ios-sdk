//
//  File.swift
//  
//
//  Created by Tomer Har Yoffi on 08/05/2024.
//

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi
@testable import CoralogixRum

class MockSpanData: SpanDataProtocol {
    var attributes: [String: Any] = [:]
    var status: String?
    var traceId: String?
    var spanId: String?
    var startTime: TimeInterval
    var endTime: TimeInterval
    
    func getStatus() -> String? {
        return self.status
    }
    
    func getEndTime() -> TimeInterval? {
        return self.endTime
    }
    
    func getStartTime() -> TimeInterval? {
        return self.startTime
    }
    
    func getTraceId() -> String? {
        return self.traceId
    }
    
    func getSpanId() -> String? {
        return self.spanId
    }
    
    func getAttribute(forKey: String) -> Any? {
        let attribute = attributes[forKey] as? AttributeValue
        return attribute?.description
    }

    // Add initializer or other methods to set up the mock data as needed
    init(attributes: [String: Any], 
         status: String? = nil,
         startTime: Date? = nil,
         endTime: Date? = nil,
         spanId: String? = nil,
         traceId: String? = nil) {
        self.attributes = attributes
        self.status = status
        self.endTime = endTime?.timeIntervalSince1970 ?? 0
        self.startTime = startTime?.timeIntervalSince1970 ?? 0
        self.traceId = traceId
        self.spanId = spanId
    }
}
