//
//  SdkFramework.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 27/07/2025.
//

import Foundation

public enum SdkFramework: Equatable {
    case swift
    case flutter(version: String)
    case reactNative(version: String)
    
    var name: String {
        switch self {
        case .swift: return "swift"
        case .flutter: return "flutter"
        case .reactNative: return "react-native"
        }
    }
    
    var isNative: Bool {
        switch self {
        case .swift:
            return true
        case .flutter, .reactNative:
            return false
        }
    }
    
    var version: String {
        switch self {
        case .flutter(let version), .reactNative(let version):
            return version
        case .swift:
            return Global.sdk.rawValue
        }
    }
    
    var nativeVersion: String {
        return isNative ? Keys.undefined.rawValue : Global.sdk.rawValue
    }
}
