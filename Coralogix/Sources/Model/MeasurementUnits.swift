//
//  MeasurementUnits.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 18/08/2025.
//

import Foundation

public enum MeasurementUnits: Equatable, Hashable {
    case milliseconds
    case kiloBytes
    case megaBytes
    case fps
    case count
    case percentage
    case custom(String)
    
    init(from string: String) {
        switch string {
        case Keys.ms.rawValue: self = .milliseconds
        case Keys.kb.rawValue: self = .kiloBytes
        case Keys.mb.rawValue: self = .megaBytes
        case Keys.fps.rawValue: self = .fps
        case Keys.count.rawValue: self = .count
        case Keys.percentage.rawValue: self = .percentage
        default: self = .custom(string)
        }
    }
    
    var stringValue: String {
        switch self {
        case .milliseconds: return Keys.ms.rawValue
        case .kiloBytes : return Keys.kb.rawValue
        case .megaBytes : return Keys.mb.rawValue
        case .fps : return Keys.fps.rawValue
        case .count : return Keys.count.rawValue
        case .percentage : return Keys.percentage.rawValue
        case .custom(let value): return value
        }
    }
}
