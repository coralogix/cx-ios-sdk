//
//  CXMobileVitalsType.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 17/08/2025.
//

import Foundation

enum CXMobileVitalsType: Equatable, Hashable {
    case cold
    case warm
    case fps
    case anr
    case metricKit
    case cpuUsagePercent
    case totalCpuTimeMs
    case mainThreadCpuTimeMs
    case residentMemoryMb
    case memoryUtilizationPercent
    case slowFramesCount
    case frozenFramesCount
    case custom(String)
    
    init(from string: String) {
        switch string {
        case Keys.cold.rawValue: self = .cold
        case Keys.warm.rawValue: self = .warm
        case Keys.fps.rawValue: self = .fps
        case Keys.anrValue.rawValue: self = .anr
        case Keys.metricKit.rawValue: self = .metricKit
        case Keys.cpuUsagePercent.rawValue: self = .cpuUsagePercent
        case Keys.totalCpuTimeMs.rawValue: self = .totalCpuTimeMs
        case Keys.mainThreadCpuTimeMs.rawValue: self = .mainThreadCpuTimeMs
        case Keys.residentMemoryMb.rawValue: self = .residentMemoryMb
        case Keys.memoryUtilizationPercent.rawValue: self = .memoryUtilizationPercent
        case Keys.slowFramesCount.rawValue: self = .slowFramesCount
        case Keys.frozenFramesCount.rawValue: self = .frozenFramesCount
        default: self = .custom(string)
        }
    }
    
    var stringValue: String {
        switch self {
        case .cold: return Keys.cold.rawValue
        case .warm: return Keys.warm.rawValue
        case .fps: return Keys.fps.rawValue
        case .anr: return Keys.anrValue.rawValue
        case .metricKit: return Keys.metricKit.rawValue
        case .cpuUsagePercent: return Keys.cpuUsagePercent.rawValue
        case .totalCpuTimeMs: return Keys.totalCpuTimeMs.rawValue
        case .mainThreadCpuTimeMs: return Keys.mainThreadCpuTimeMs.rawValue
        case .residentMemoryMb: return Keys.residentMemoryMb.rawValue
        case .memoryUtilizationPercent: return Keys.memoryUtilizationPercent.rawValue
        case .slowFramesCount: return Keys.slowFramesCount.rawValue
        case .frozenFramesCount: return Keys.frozenFramesCount.rawValue
        case .custom(let value): return value
        }
    }
}

extension CXMobileVitalsType {
    var spanAttributes: [String: AttributeValue] {
        switch self {
        case .anr:
            return [
                Keys.eventType.rawValue: .string(CoralogixEventType.error.rawValue),
                Keys.source.rawValue: .string(Keys.console.rawValue),
                Keys.severity.rawValue: .int(CoralogixLogSeverity.error.rawValue)
            ]
        default:
            return [
                Keys.eventType.rawValue: .string(CoralogixEventType.mobileVitals.rawValue),
                Keys.severity.rawValue: .int(CoralogixLogSeverity.info.rawValue)
            ]
        }
    }
    
    func specificAttributes(for value: String) -> [String: AttributeValue] {
        switch self {
        case .anr:
            return [
                Keys.errorMessage.rawValue: .string(Keys.anr.rawValue)
            ]
        default:
            return [
                Keys.mobileVitalsValue.rawValue: .string(value)
            ]
        }
    }
}
