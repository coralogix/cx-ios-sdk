//
//  EventContext.swift
//  Elastiflix-iOS
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import OpenTelemetrySdk

struct EventContext {
    var type: CoralogixEventType = .unknown
    let source: String
    var severity: Int = 0
    
    init(otel: SpanData) {
        if let type = otel.attributes[Keys.eventType.rawValue]?.description {
            self.type = CoralogixEventType(rawValue: type) ?? .unknown
        }
        
        self.source = otel.attributes[Keys.source.rawValue]?.description ?? ""
        
        if let severity = otel.attributes[Keys.severity.rawValue]?.description {
            self.severity = Int(severity) ?? 0
        }
    }
    
    func getDictionary() -> [String: Any] {
        return [Keys.type.rawValue: self.type.rawValue,
                Keys.source.rawValue: self.source,
                Keys.severity.rawValue: self.severity]
    }
}
