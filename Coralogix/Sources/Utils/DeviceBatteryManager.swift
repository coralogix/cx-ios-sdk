//
//  DeviceBatteryManager.swift
//
//
//  Created by Coralogix DEV TEAM on 12/05/2024.
//
#if canImport(UIKit)
import UIKit
#endif

class DeviceBatteryManager {

    init() {
        // Enable battery monitoring
        #if os(iOS)
            UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
    }

    deinit {
        // Disable battery monitoring when not needed to save power
#if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = false
#endif
    }

    public func getBatteryLevel() -> Float {
    #if os(tvOS)
    Log.d("Battery level is not applicable on tvOS")
    return -1.0 // or return 0.0 to indicate no battery
    #else
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel < 0 {
            // If battery level is -1.0, the battery level is unknown.
            Log.d("Battery level is unknown")
        } else {
            Log.d("Battery level is \(batteryLevel * 100)%")
        }
        return batteryLevel
    #endif
    }
}
