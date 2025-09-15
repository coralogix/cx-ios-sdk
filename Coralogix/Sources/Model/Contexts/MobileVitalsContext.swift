//
//  MobileVitalsContext.swift
//
//
//  Created by Coralogix DEV TEAM on 10/09/2024.
//

import Foundation
import CoralogixInternal

struct MobileVitalsContext {
    var mobileVitalsType: [String: Any]?
   
    init(otel: SpanDataProtocol) {
        if let jsonString = otel.getAttribute(forKey: Keys.mobileVitalsType.rawValue) as? String,
           let mobileVitalsType = Helper.convertJsonStringToDict(jsonString: jsonString) {
            self.mobileVitalsType = mobileVitalsType
        }
    }
    
    func getMobileVitalsDictionary() -> [String: Any] {
        return mobileVitalsType ?? [:]
    }
}
