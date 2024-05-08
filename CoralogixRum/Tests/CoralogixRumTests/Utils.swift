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
    var endTime: TimeInterval
    
    func getStatus() -> String? {
        return self.status
    }
    
    func getDuration() -> TimeInterval? {
        return self.endTime
    }
    
    func getAttribute(forKey: String) -> Any? {
        let attribute = attributes[forKey] as? AttributeValue
        return attribute?.description
    }

    // Add initializer or other methods to set up the mock data as needed
    init(attributes: [String: Any], status: String? = nil, endTime: Date? = nil) {
        self.attributes = attributes
        self.status = status
        self.endTime = endTime?.timeIntervalSince1970 ?? 0
    }
}
