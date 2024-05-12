//
//  NetworkManager.swift
//
//
//  Created by Tomer Har Yoffi on 12/05/2024.
//

import Foundation
import Network
import CoreTelephony

public class NetworkManager {
    let monitor = NWPathMonitor()
    var networkType = "No connection or unknown type"
    
    init() {
        self.checkConnectionType()
        monitor.start(queue: .main)
    }
    
    func checkConnectionType() {
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
            case CTRadioAccessTechnologyNRNSA,
                 CTRadioAccessTechnologyNR:
                return "5G"
            default:
                return "Unknown"
            }
        }
        return "Not Cellular Connection"
    }
}
