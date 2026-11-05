//
//  NetworkManager.swift
//
//
//  Created by Coralogix DEV TEAM on 12/05/2024.
//

import Foundation
import Network
#if canImport(CoreTelephony)
import CoreTelephony
#endif

public protocol NetworkProtocol {
    func getNetworkType() -> String
}

/// Whether the device has a usable network path right now. Internal on purpose: crash delivery
/// needs it to decide whether a failed upload counts, but `NetworkProtocol` is public and may
/// have conformers outside the SDK.
protocol NetworkReachability: AnyObject {
    var isOnline: Bool { get }
}

public class NetworkManager: NetworkProtocol, NetworkReachability {
    let monitor = NWPathMonitor()
    var networkType = "No connection or unknown type"
    
    init() {
        self.checkConnectionType()
        monitor.start(queue: .main)
    }
    
    public func getNetworkType() -> String {
        return self.networkType
    }

    /// `currentPath` is safe to read from any thread once the monitor has started.
    var isOnline: Bool {
        monitor.currentPath.status == .satisfied
    }
    
    private func checkConnectionType() {
        self.monitor.pathUpdateHandler = { path in
            if path.usesInterfaceType(.wifi) {
                self.networkType = "WiFi"
            } else if path.usesInterfaceType(.cellular) {
                self.networkType = "Cellular"
                let networkType = self.getCellularNetworkType()
                self.networkType = "Cellular: \(networkType)"
            } else if path.usesInterfaceType(.wiredEthernet) {
                self.networkType = "Ethernet"
            } else {
                self.networkType = "No connection or unknown type"
            }
        }
    }
    
    func getCellularNetworkType() -> String {
#if targetEnvironment(simulator) || !canImport(CoreTelephony)
        return "Unknown"
#else
        let networkInfo = CTTelephonyNetworkInfo()
        let currentRadioTech = networkInfo.serviceCurrentRadioAccessTechnology
        if let radioTech = currentRadioTech?.values.first {
            switch radioTech {
            case CTRadioAccessTechnologyGPRS,
                CTRadioAccessTechnologyEdge,
            CTRadioAccessTechnologyCDMA1x:
                return "2G"
            case CTRadioAccessTechnologyWCDMA,
                CTRadioAccessTechnologyHSDPA,
                CTRadioAccessTechnologyHSUPA,
                CTRadioAccessTechnologyCDMAEVDORev0,
                CTRadioAccessTechnologyCDMAEVDORevA,
                CTRadioAccessTechnologyCDMAEVDORevB,
            CTRadioAccessTechnologyeHRPD:
                return "3G"
            case CTRadioAccessTechnologyLTE:
                return "4G"
           
            default:
                // Use iOS 14.1+ checks for 5G support
                if #available(iOS 14.1, *) {
                    switch radioTech {
                    case CTRadioAccessTechnologyNRNSA, CTRadioAccessTechnologyNR:
                        return "5G"
                    default:
                        return "Unknown"
                    }
                } else {
                    return "Unknown" // iOS versions below 14.1
                }
            }
        }
        return "Not Cellular Connection"
#endif
    }
}
