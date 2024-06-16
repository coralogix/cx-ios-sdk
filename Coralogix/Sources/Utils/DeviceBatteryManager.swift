//
//  DeviceBatteryManager.swift
//
//
//  Created by Coralogix DEV TEAM on 12/05/2024.
//

import UIKit

class DeviceBatteryManager {

    init() {
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    deinit {
        // Disable battery monitoring when not needed to save power
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    public func getBatteryLevel() -> Float {
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel < 0 {
            // If battery level is -1.0, the battery level is unknown.
            Log.d("Battery level is unknown")
        } else {
            Log.d("Battery level is \(batteryLevel * 100)%")
        }
        return batteryLevel
    }
}
