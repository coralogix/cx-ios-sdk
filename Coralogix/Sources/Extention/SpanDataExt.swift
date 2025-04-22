//
//  SpanDataExt.swift
//
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import Foundation
import CoralogixInternal

protocol SpanDataProtocol {
    func getAttribute(forKey: String) -> Any?
    func getStatusCode() -> [String: Any]
    func getStartTime() -> TimeInterval?
    func getEndTime() -> TimeInterval?
    func getTraceId() -> String?
    func getSpanId() -> String?
    func getAttributes() -> [String: Any]?
    func getName() -> String?
    func getKind() -> Int
    func getResources() -> [String: Any]
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
    
    func getStatusCode() -> [String: Any] {
        let status: Status = self.status
        var code = 0
        switch status {
        case .ok:
            code = 1
        case .unset:
            code = 0
        case .error:
            code = 2
        }
        return [Keys.code.rawValue: code]
    }
    
    func getStartTime() -> TimeInterval? {
        return self.startTime.timeIntervalSince1970
    }
    
    func getEndTime() -> TimeInterval? {
        return self.endTime.timeIntervalSince1970
    }
    
    func getAttribute(forKey key: String) -> Any? {
        return self.attributes[key]?.description
    }
    
    func getAttributes() -> [String: Any]? {
        return Helper.convertToAnyDict(self.attributes)
    }
    
    func getName() -> String? {
        return self.name
    }
    
    func getKind() -> Int {
        return 2 // 2 means Client
    }
    
    func getResources() -> [String: Any] {
        return Helper.convertToAnyDict(self.resource.attributes) 
    }
}
