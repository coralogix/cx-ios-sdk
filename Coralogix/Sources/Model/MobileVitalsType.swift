//
//  MobileVitalsType.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 17/08/2025.
//

import Foundation

enum MobileVitalsType: Equatable, Hashable {
    case cold //Ms
    case warm //Ms
    case fps  //Fps
    case anr
    case metricKit
    case cpuUsage //Percent
    case totalCpuTime //Ms
    case mainThreadCpuTime //Ms
    case residentMemory //Mb
    case footprintMemory //Mb
    case memoryUtilization //Percent
    case slowFrames //Count
    case frozenFrames //Count
    case custom(String)
    
    init(from string: String) {
        switch string {
        case Keys.cold.rawValue: self = .cold
        case Keys.warm.rawValue: self = .warm
        case Keys.fps.rawValue: self = .fps
        case Keys.anr.rawValue: self = .anr
        case Keys.metricKit.rawValue: self = .metricKit
        case Keys.cpuUsage.rawValue: self = .cpuUsage
        case Keys.totalCpuTime.rawValue: self = .totalCpuTime
        case Keys.mainThreadCpuTime.rawValue: self = .mainThreadCpuTime
        case Keys.residentMemory.rawValue: self = .residentMemory
        case Keys.memoryUtilization.rawValue: self = .memoryUtilization
        case Keys.slowFrames.rawValue: self = .slowFrames
        case Keys.frozenFrames.rawValue: self = .frozenFrames
        case Keys.footprintMemory.rawValue: self = .footprintMemory
        default: self = .custom(string)
        }
    }
    
    var stringValue: String {
        switch self {
        case .cold: return Keys.cold.rawValue
        case .warm: return Keys.warm.rawValue
        case .fps: return Keys.fps.rawValue
        case .anr: return Keys.anr.rawValue
        case .metricKit: return Keys.metricKit.rawValue
        case .cpuUsage: return Keys.cpuUsage.rawValue
        case .totalCpuTime: return Keys.totalCpuTime.rawValue
        case .mainThreadCpuTime: return Keys.mainThreadCpuTime.rawValue
        case .residentMemory: return Keys.residentMemory.rawValue
        case .memoryUtilization: return Keys.memoryUtilization.rawValue
        case .slowFrames: return Keys.slowFrames.rawValue
        case .frozenFrames: return Keys.frozenFrames.rawValue
        case .footprintMemory: return Keys.footprintMemory.rawValue
        case .custom(let value): return value
        }
    }
}
