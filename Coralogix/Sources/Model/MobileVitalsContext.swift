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
    let mobileVitalsName: String?
    let mobileVitalsValue: String
    let mobileVitalsUuid: String?
    let mobileVitalsUnits: String
    
    init(otel: SpanDataProtocol) {
        self.mobileVitalsType = otel.getAttribute(forKey: Keys.mobileVitalsType.rawValue) as? String ?? Keys.undefined.rawValue
        self.mobileVitalsName = otel.getAttribute(forKey: Keys.name.rawValue) as? String
        self.mobileVitalsValue = otel.getAttribute(forKey: Keys.mobileVitalsValue.rawValue) as? String ?? Keys.undefined.rawValue
        self.mobileVitalsUuid = otel.getAttribute(forKey: Keys.mobileVitalsUuid.rawValue) as? String
        self.mobileVitalsUnits = otel.getAttribute(forKey: Keys.mobileVitalsUnits.rawValue) as? String ?? Keys.undefined.rawValue
    }
    
    func getMobileVitalsDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.type.rawValue] = self.mobileVitalsType
        
        if let name = self.mobileVitalsName, !name.isEmpty {
            result[Keys.name.rawValue] = name
        }
        
        result[Keys.value.rawValue] = Global.format(Double(self.mobileVitalsValue) ?? 0.0)
        
        if let uuid = self.mobileVitalsUuid, !uuid.isEmpty {
            result[Keys.mobileVitalsUuid.rawValue] = uuid
        }
        result[Keys.mobileVitalsUnits.rawValue] = self.mobileVitalsUnits

        return result
    }
}
