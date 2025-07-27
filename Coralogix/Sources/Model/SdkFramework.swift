//
//  SdkFramework.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 27/07/2025.
//

import Foundation

public enum SdkFramework: Equatable {
    case swift
    case flutter
    case reactNative
    case hybrid(HybridFramework)
    
    public enum HybridFramework: Equatable {
        case flutter(version: String)
        case reactNative(version: String)
    }
    
    var name: String {
        switch self {
        case .swift: return "swift"
        case .flutter: return "flutter"
        case .reactNative: return "react-native"
        case .hybrid(let hybridFramework):
            switch hybridFramework {
            case .flutter: return "flutter"
            case .reactNative: return "react-native"
            }
        }
    }
    
    var isNative: Bool {
        switch self {
        case .swift:
            return true
        case .flutter, .reactNative, .hybrid:
            return false
        }
    }
    
    var version: String? {
        switch self {
        case .hybrid(let hybridFramework):
            switch hybridFramework {
            case .flutter(let version), .reactNative(let version):
                return version
            }
        case .swift:
            return Global.sdk.rawValue
        default:
            return nil
        }
    }
    
    var nativeVersion: String? {
        return isNative ? nil : version
    }
}
