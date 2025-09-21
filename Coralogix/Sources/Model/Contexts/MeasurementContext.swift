//
//  MeasurementContext.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 18/09/2025.
//

import Foundation
import CoralogixInternal

struct MeasurementContext {
    let name: String
    let value: Double?
    
    init(otel: SpanDataProtocol) {
        self.name = otel.getAttribute(forKey: Keys.name.rawValue) as? String ?? ""
        let raw = otel.getAttribute(forKey: Keys.value.rawValue) as? String ?? ""
        if let d = raw as? Double {
            self.value = d
        } else {
            self.value = nil
        }
    }
    
    func isValid() -> Bool {
        return !name.isEmpty
    }
    
    func getDictionary() -> [String: Any] {
        var result: [String: Any] = [Keys.name.rawValue: name]
        if let value = value {
            result[Keys.value.rawValue] = value
        }
        return result
    }
}
