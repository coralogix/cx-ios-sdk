//
//  HybridMetric.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 18/08/2025.
//

import Foundation

public struct HybridMetric {
    public let name: String
    public let value: Double
    public let units: String
    
    public init(name: String, value: Double, units: String) {
        self.name = name
        self.value = value
        self.units = units
    }
}
