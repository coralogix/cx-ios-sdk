//
//  DeviceState.swift
//
//
//  Created by Coralogix DEV TEAM on 12/05/2024.
//

import Foundation

struct DeviceState {
    let battery: String
    let networkType: String
    let deviceBatteryManager = DeviceBatteryManager()
    
    init(networkManager: NetworkManager?) {
        self.battery = String(deviceBatteryManager.getBatteryLevel())
        self.networkType = networkManager?.networkType ?? ""
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.networkType.rawValue] = self.networkType
        result[Keys.battery.rawValue] = self.battery
        return result
    }
}
