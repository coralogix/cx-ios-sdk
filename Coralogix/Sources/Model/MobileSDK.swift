//
//  MobileSDK.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 27/07/2025.
//

import Foundation

public struct MobileSDK {
    var sdkFramework: SdkFramework
    
    public init(sdkFramework: SdkFramework = .swift) {
        self.sdkFramework = sdkFramework
    }

    public func getDictionary() -> [String: Any] {
        if sdkFramework == .swift {
            return [Keys.sdkVersion.rawValue: sdkFramework.version,
                    Keys.framework.rawValue: sdkFramework.name,
                    Keys.operatingSystem.rawValue: Global.getOs()]
        } else {
            return [Keys.sdkVersion.rawValue: sdkFramework.version,
                    Keys.nativeVersion.rawValue: sdkFramework.nativeVersion,
                    Keys.framework.rawValue: sdkFramework.name,
                    Keys.operatingSystem.rawValue: Global.getOs()]
        }
    }
}
