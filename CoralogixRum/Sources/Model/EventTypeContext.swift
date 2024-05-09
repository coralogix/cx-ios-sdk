//
//  EventTypeContext.swift
//
//  Created by Coralogix DEV TEAM on 01/04/2024.
//

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi

struct EventTypeContext {
    let method: String
    var statusCode: Int = 0
    let url: String
    let fragments: String
    let host: String
    var schema: String
    let statusText: String
    let duration: TimeInterval
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
        self.statusText = otel.getStatus() ?? ""
        self.duration = otel.getEndTime() ?? 0
        self.responseContentLength = otel.getAttribute(forKey: SemanticAttributes.httpResponseBodySize.rawValue) as? String ?? ""
    }
    
    func getDictionary() -> [String: Any] {
        return [Keys.method.rawValue: self.method,
                Keys.statusCode.rawValue: self.statusCode,
                Keys.url.rawValue: self.url,
                Keys.fragments.rawValue: self.fragments,
                Keys.host.rawValue: self.host,
                Keys.schema.rawValue: self.schema,
                Keys.statusText.rawValue: self.statusText,
                Keys.duration.rawValue: self.duration.milliseconds,
                Keys.responseContentLength.rawValue: self.responseContentLength]
    }
}
