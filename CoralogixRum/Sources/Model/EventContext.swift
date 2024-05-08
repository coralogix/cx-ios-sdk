//
//  EventContext.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import OpenTelemetrySdk

struct EventContext {
    var type: CoralogixEventType = .unknown
    let source: String
    var severity: Int = 0
    
    init(otel: SpanDataProtocol) {
        if let type = otel.getAttribute(forKey: Keys.eventType.rawValue) as? String {
            self.type = CoralogixEventType(rawValue: type) ?? .unknown
        }
        
        self.source = otel.getAttribute(forKey: Keys.source.rawValue) as? String ?? ""
        
        if let severity = otel.getAttribute(forKey:Keys.severity.rawValue) as? String {
            self.severity = Int(severity) ?? 0
        }
    }
    
    func getDictionary() -> [String: Any] {
        return [Keys.type.rawValue: self.type.rawValue,
                Keys.source.rawValue: self.source,
                Keys.severity.rawValue: self.severity]
    }
}
