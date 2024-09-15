//
//  MockSpanData.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import Foundation
@testable import Coralogix

class MockSpanData: SpanDataProtocol {
    var attributes: [String: Any] = [:]
    var status: String?
    var traceId: String?
    var spanId: String?
    var startTime: TimeInterval
    var endTime: TimeInterval
    var statusCode: [String: Any] = [:]
    var name: String?
    var resources: [String: Any] = [:]
    var kind: Int
    
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
    
    func getStatusCode() -> [String : Any] {
        return self.statusCode
    }
    
    func getAttributes() -> [String : Any]? {
        return self.attributes
    }
    
    func getName() -> String? {
        return self.name
    }
    
    func getKind() -> Int {
        return self.kind
    }
    
    func getResources() -> [String : Any] {
        return self.resources
    }

    // Add initializer or other methods to set up the mock data as needed
    init(attributes: [String: Any], 
         status: String? = nil,
         startTime: Date? = nil,
         endTime: Date? = nil,
         spanId: String? = nil,
         traceId: String? = nil,
         name: String? = nil,
         kind: Int = 0,
         statusCode: [String: Any]? = nil,
         resources: [String: Any]? = nil) {
        self.attributes = attributes
        self.status = status
        self.endTime = endTime?.timeIntervalSince1970 ?? 0
        self.startTime = startTime?.timeIntervalSince1970 ?? 0
        self.traceId = traceId
        self.spanId = spanId
        self.kind = kind
        self.name = name
        self.traceId = traceId
        self.statusCode = statusCode ?? [:]
        self.resources = resources ?? [:]
    }
}

class MockKeyschainManager: KeyChainProtocol {
    var pid = ""
    var sessionId = ""
    var sessionTimeInterval = ""
    
    func readStringFromKeychain(service: String, key: String) -> String? {
        if key == "pid" {
            return self.pid
        } else if key == "sessionId" {
            return self.sessionId
        } else if key == "sessionTimeInterval" {
            return self.sessionTimeInterval
        }
        return nil
    }
    
    func writeStringToKeychain(service: String, key: String, value: String) {
        if key == "pid" {
            self.pid = value
        } else if key == "sessionId" {
            self.sessionId = value
        } else if key == "sessionTimeInterval" {
            self.sessionTimeInterval = value
        }
    }
}

class MockNetworkManager: NetworkProtocol {
    func getNetworkType() -> String {
        return "5G"
    }
}
