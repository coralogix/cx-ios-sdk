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

    /// Whether the RUM ingest schema accepts the detailed native-crash
    /// `error_context` fields (threads, exception_type, arch, build_id, …) for
    /// this framework. Allowed for native iOS and Flutter; rejected for
    /// React Native (CX-46601), where they must be omitted to avoid an HTTP 400.
    var allowsNativeCrashContext: Bool {
        switch self {
        case .swift, .flutter:
            return true
        case .reactNative:
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
