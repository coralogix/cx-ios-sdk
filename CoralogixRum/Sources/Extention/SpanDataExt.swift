//
//  SpanDataExt.swift
//
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import Foundation
import OpenTelemetrySdk

protocol SpanDataProtocol {
    func getAttribute(forKey: String) -> Any?
    func getStatus() -> String?
    func getStartTime() -> TimeInterval?
    func getEndTime() -> TimeInterval?
    func getTraceId() -> String?
    func getSpanId() -> String?
}

// Extend the real SpanData to conform to this protocol if possible
// This is only necessary if SpanData doesn't already have the methods you need
extension SpanData: SpanDataProtocol {
    func getTraceId() -> String? {
        return self.traceId.hexString
    }
    
    func getSpanId() -> String? {
        return self.spanId.hexString
    }
    
    func getStatus() -> String? {
        return self.status.description
    }
    
    func getStartTime() -> TimeInterval? {
        return self.startTime.timeIntervalSince1970
    }
    
    func getEndTime() -> TimeInterval? {
        return self.endTime.timeIntervalSinceReferenceDate
    }
    
    func getAttribute(forKey key: String) -> Any? {
        return self.attributes[key]?.description
    }
}
