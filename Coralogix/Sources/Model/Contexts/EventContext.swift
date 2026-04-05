//
//  EventContext.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import CoralogixInternal

struct EventContext {
    var type: CoralogixEventType = .unknown
    let source: String
    /// Default **info** (3) when the span omits `severity` or it is not a valid integer (matches top-level log `severity`).
    var severity: Int = CoralogixLogSeverity.info.rawValue
    
    init(otel: SpanDataProtocol) {
        if let type = otel.getAttribute(forKey: Keys.eventType.rawValue) as? String {
            self.type = CoralogixEventType(rawValue: type) ?? .unknown
        }
        
        self.source = otel.getAttribute(forKey: Keys.source.rawValue) as? String ?? ""
        
        if let severityStr = otel.getAttribute(forKey: Keys.severity.rawValue) as? String,
           let parsed = Int(severityStr) {
            self.severity = parsed
        }
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.type.rawValue] = self.type.rawValue
        
        if self.source != "" {
            result[Keys.source.rawValue] = self.source
        }
        
        result[Keys.severity.rawValue] = self.severity
        return result
    }
}
