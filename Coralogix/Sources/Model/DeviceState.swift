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
    
    init(networkManager: NetworkProtocol?) {
        self.battery = Helper.isSimulator ? "" : String(deviceBatteryManager.getBatteryLevel())
        self.networkType = networkManager?.getNetworkType() ?? ""
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.networkType.rawValue] = self.networkType
        result[Keys.battery.rawValue] = self.battery
        return result
    }
}
