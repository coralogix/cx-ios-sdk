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
    let value: String
    
    init(otel: SpanDataProtocol) {
        self.name = otel.getAttribute(forKey: Keys.name.rawValue) as? String ?? ""
        self.value = otel.getAttribute(forKey: Keys.value.rawValue) as? String ?? ""
    }
    
    func isValid() -> Bool {
        return !name.isEmpty
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.name.rawValue] = name
        result[Keys.value.rawValue] = Double(value) ?? 0.0
        return result
    }
}
