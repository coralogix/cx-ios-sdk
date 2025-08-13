//
//  MobileVitalsContext.swift
//
//
//  Created by Coralogix DEV TEAM on 10/09/2024.
//

import Foundation
import CoralogixInternal

struct MobileVitalsContext {
    let mobileVitalsType: String
    let mobileVitalsValue: String
    let mobileVitalsUuid: String?
    
    init(otel: SpanDataProtocol) {
        self.mobileVitalsType = otel.getAttribute(forKey: Keys.mobileVitalsType.rawValue) as? String ?? ""
        self.mobileVitalsValue = otel.getAttribute(forKey: Keys.mobileVitalsValue.rawValue) as? String ?? ""
        self.mobileVitalsUuid = otel.getAttribute(forKey: Keys.mobileVitalsUuid.rawValue) as? String
    }
    
    func getMobileVitalsDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.type.rawValue] = self.mobileVitalsType
        result[Keys.value.rawValue] = self.mobileVitalsValue
        if let uuid = self.mobileVitalsUuid, !uuid.isEmpty {
            result[Keys.mobileVitalsUuid.rawValue] = uuid
        }
        return result
    }
}
