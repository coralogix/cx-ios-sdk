//
//  LifeCycleContext.swift
//
//
//  Created by Coralogix DEV TEAM on 17/11/2024.
//

import Foundation
import CoralogixInternal

struct LifeCycleContext {
    let lifeCycleType: String
    
    init(otel: SpanDataProtocol) {
        self.lifeCycleType = otel.getAttribute(forKey: Keys.type.rawValue) as? String ?? ""
    }
    
    func getLifeCycleDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.eventName.rawValue] = self.lifeCycleType
        return result
    }
}
