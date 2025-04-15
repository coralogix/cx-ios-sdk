//
//  EventTypeContext.swift
//
//  Created by Coralogix DEV TEAM on 01/04/2024.
//

import Foundation
import CoralogixInternal

struct EventTypeContext {
    let method: String
    var statusCode: Int = 0
    let url: String
    let fragments: String
    let host: String
    var schema: String
    let duration: UInt64
    let responseContentLength: String
    
    init(otel: SpanDataProtocol) {
        self.method = otel.getAttribute(forKey: SemanticAttributes.httpMethod.rawValue) as? String ?? ""
        
        if let statusCode = otel.getAttribute(forKey: SemanticAttributes.httpStatusCode.rawValue) as? String {
            self.statusCode = Int(statusCode) ?? 0
        }
        
        self.url = otel.getAttribute(forKey: SemanticAttributes.httpUrl.rawValue) as? String ?? ""
        self.fragments = otel.getAttribute(forKey: SemanticAttributes.httpTarget.rawValue) as? String ?? ""
        self.host = otel.getAttribute(forKey: SemanticAttributes.netPeerName.rawValue) as? String ?? ""
        self.schema = otel.getAttribute(forKey: SemanticAttributes.httpScheme.rawValue) as? String ?? ""
        if let startTime = otel.getStartTime(),
           let endTime = otel.getEndTime() {
            let delta = endTime - startTime
            self.duration = delta.openTelemetryMilliseconds
        } else {
            self.duration = 0
        }
        self.responseContentLength = otel.getAttribute(forKey: SemanticAttributes.httpResponseBodySize.rawValue) as? String ?? ""
    }
    
    func getDictionary() -> [String: Any] {
        return [Keys.method.rawValue: self.method,
                Keys.statusCode.rawValue: self.statusCode,
                Keys.url.rawValue: self.url,
                Keys.fragments.rawValue: self.fragments,
                Keys.host.rawValue: self.host,
                Keys.schema.rawValue: self.schema,
                Keys.duration.rawValue: self.duration,
                Keys.responseContentLength.rawValue: self.responseContentLength]
    }
}
