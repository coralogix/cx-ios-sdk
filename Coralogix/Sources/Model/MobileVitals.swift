//
//  MobileVitals.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 19/08/2025.
//

import Foundation

struct MobileVitals {
    let type: MobileVitalsType
    let name: String?
    let value: Double
    let uuid: String?
    let units: MeasurementUnits
    
    init(type: MobileVitalsType,
         name: String? = nil,
         value: Double,
         units: MeasurementUnits,
         uuid: String? = nil) {
        self.type = type
        self.name = name
        self.value = value
        self.units = units
        self.uuid = uuid
    }
}
