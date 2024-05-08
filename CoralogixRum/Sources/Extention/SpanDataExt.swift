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
    func getDuration() -> TimeInterval?
}

// Extend the real SpanData to conform to this protocol if possible
// This is only necessary if SpanData doesn't already have the methods you need
extension SpanData: SpanDataProtocol {
    func getStatus() -> String? {
        return self.status.description
    }
    
    func getDuration() -> TimeInterval? {
        return self.endTime.timeIntervalSinceReferenceDate
    }
    
    func getAttribute(forKey key: String) -> Any? {
        return self.attributes[key]?.description
    }
}
