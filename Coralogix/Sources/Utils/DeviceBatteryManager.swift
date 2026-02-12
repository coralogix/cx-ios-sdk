//
//  DeviceBatteryManager.swift
//
//
//  Created by Coralogix DEV TEAM on 12/05/2024.
//
#if canImport(UIKit)
import UIKit
#endif
import CoralogixInternal

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
    return -1.0 // Battery level not applicable on tvOS
    #else
        let batteryLevel = UIDevice.current.batteryLevel
        return batteryLevel
    #endif
    }
}
