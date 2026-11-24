//
//  DoubleExt.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 30/10/2025.
//

import Foundation

public extension Double {
    /// Returns the number rounded to a specified number of decimal places.
    func roundedTo(to places: Int = 2) -> Double {
        guard places >= 0 else { return self }   // ✅ prevent crash in prod
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}








