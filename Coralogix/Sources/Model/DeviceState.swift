//
//  DeviceState.swift
//
//
//  Created by Coralogix DEV TEAM on 12/05/2024.
//

import Foundation
import CoralogixInternal

struct DeviceState {
    let battery: String
    let networkType: String
    let deviceBatteryManager = DeviceBatteryManager()
    
    init(networkManager: NetworkProtocol?) {
#if targetEnvironment(simulator)
        self.battery = ""
#else
        self.battery = String(deviceBatteryManager.getBatteryLevel())
#endif
        self.networkType = networkManager?.getNetworkType() ?? ""
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.networkType.rawValue] = self.networkType
        result[Keys.battery.rawValue] = self.battery
        return result
    }
}
