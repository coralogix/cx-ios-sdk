//
//  EventTypeContext.swift
//  Elastiflix-iOS
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
    
    init(otel: SpanData) {
        self.method = otel.attributes[SemanticAttributes.httpMethod.rawValue]?.description ?? ""
        
        if let statusCode = otel.attributes[SemanticAttributes.httpStatusCode.rawValue]?.description {
            self.statusCode = Int(statusCode) ?? 0
        }
        
        self.url = otel.attributes[SemanticAttributes.httpUrl.rawValue]?.description ?? ""
        self.fragments = otel.attributes[SemanticAttributes.httpTarget.rawValue]?.description ?? ""
        self.host = otel.attributes[SemanticAttributes.netPeerName.rawValue]?.description ?? ""
        self.schema = otel.attributes[SemanticAttributes.httpScheme.rawValue]?.description ?? ""
        self.statusText = otel.status.description
        self.duration = otel.endTime.timeIntervalSinceReferenceDate
        self.responseContentLength = otel.attributes[SemanticAttributes.httpResponseBodySize.rawValue]?.description ?? ""
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
