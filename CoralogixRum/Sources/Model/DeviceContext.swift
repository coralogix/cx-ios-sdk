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
    
    init(otel: SpanDataProtocol) {
        self.networkConnectionType = otel.getAttribute(forKey: SemanticAttributes.networkConnectionType.rawValue) as? String ?? ""
        self.networkConnectionSubtype = otel.getAttribute(forKey: SemanticAttributes.networkConnectionSubtype.rawValue) as? String ?? ""
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.networkConnectionType.rawValue] = self.networkConnectionType
        result[Keys.networkConnectionSubtype.rawValue] = self.networkConnectionSubtype
        return result
    }
}
