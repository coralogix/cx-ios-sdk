//
//  DeviceContext.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi

struct DeviceContext {
    let networkConnectionType: String
    let networkConnectionSubtype: String
    
    init(otel: SpanData) {
        self.networkConnectionType = otel.attributes[SemanticAttributes.networkConnectionType.rawValue]?.description ?? ""
        self.networkConnectionSubtype = otel.attributes[SemanticAttributes.networkConnectionSubtype.rawValue]?.description ?? ""
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.networkConnectionType.rawValue] = self.networkConnectionType
        result[Keys.networkConnectionSubtype.rawValue] = self.networkConnectionSubtype
        return result
    }
}
