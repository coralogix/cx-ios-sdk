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
    /// Called when the network comes back after the device was offline.
    var onReconnect: (() -> Void)? { get set }
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

    private let pathLock = NSLock()
    /// Whether the monitor has evaluated a path yet. Until it has, `currentPath` reads
    /// unsatisfied whatever the network is.
    private var hasPath = false
    private var wasOnline = true
    private var _onReconnect: (() -> Void)?

    var onReconnect: (() -> Void)? {
        get { pathLock.lock(); defer { pathLock.unlock() }; return _onReconnect }
        set { pathLock.lock(); defer { pathLock.unlock() }; _onReconnect = newValue }
    }

    /// Records a path evaluation; calls `onReconnect` when it ends a spell offline. The first
    /// evaluation ends none: until then the network counted as online.
    func pathChanged(satisfied: Bool) {
        pathLock.lock()
        let reconnected = !wasOnline && satisfied
        hasPath = true
        wasOnline = satisfied
        let handler = reconnected ? _onReconnect : nil
        pathLock.unlock()
        handler?()
    }

    /// `currentPath` is safe to read from any thread once the monitor has started. Before its
    /// first evaluation the network is unknown, which counts as online, as when there is no monitor.
    var isOnline: Bool {
        pathLock.lock()
        let known = hasPath
        pathLock.unlock()
        return !known || monitor.currentPath.status == .satisfied
    }
    
    private func checkConnectionType() {
        self.monitor.pathUpdateHandler = { path in
            self.pathChanged(satisfied: path.status == .satisfied)
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
