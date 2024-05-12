//
//  DeviceContext.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi
import UIKit

struct DeviceContext {
    let networkConnectionType: String
    let networkConnectionSubtype: String
    let operatingSystem: String
    let osVersion: String
    let emulator: Bool
    let deviceName: String
    let deviceModel: String
    
    init(otel: SpanDataProtocol) {
        self.networkConnectionType = otel.getAttribute(forKey: SemanticAttributes.networkConnectionType.rawValue) as? String ?? ""
        self.networkConnectionSubtype = otel.getAttribute(forKey: SemanticAttributes.networkConnectionSubtype.rawValue) as? String ?? ""
        self.deviceModel = Global.getDeviceModel()
        self.operatingSystem = Global.getOs()
        self.osVersion = Global.osVersionInfo()
        self.emulator = Global.isEmulator()
        self.deviceName = Global.getDeviceName()
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        if !self.networkConnectionType.isEmpty {
            result[Keys.networkConnectionType.rawValue] = self.networkConnectionType
        }
        
        if !self.networkConnectionSubtype.isEmpty {
            result[Keys.networkConnectionSubtype.rawValue] = self.networkConnectionSubtype
        }
        
        result[Keys.device.rawValue] = self.deviceModel
        result[Keys.deviceName.rawValue] = self.deviceName
        result[Keys.emulator.rawValue] = self.emulator
        result[Keys.operatingSystem.rawValue] = self.operatingSystem
        result[Keys.osVersion.rawValue] = self.osVersion
        return result
    }
}
