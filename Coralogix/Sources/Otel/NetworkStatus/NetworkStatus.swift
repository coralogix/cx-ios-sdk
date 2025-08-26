/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if os(iOS) && !targetEnvironment(macCatalyst)
import CoreTelephony
import Foundation
import Network

public class NetworkStatusClass {
    public private(set) var networkInfo: CTTelephonyNetworkInfo?
    public private(set) var networkMonitor: NetworkMonitorProtocol
    
    public convenience init() throws {
        self.init(with: try NetworkMonitor())
    }

    public init(with monitor: NetworkMonitorProtocol) {
        networkMonitor = monitor
#if targetEnvironment(simulator)
        networkInfo = nil
#else
        networkInfo = CTTelephonyNetworkInfo()
#endif
    }

    public func status() -> (String, String?, Any?) {
        var result: (String, String?, Any?) = ("unavailable", nil, nil)
        
        let fetchStatus = {
            switch self.networkMonitor.getConnection() {
            case .wifi:
                result = ("wifi", nil, nil)
            case .cellular:
                if #available(iOS 16.0, *) {
                    if let networkInfo = self.networkInfo,
                       let serviceId = networkInfo.dataServiceIdentifier,
                       let radioAccessTechnology = networkInfo.serviceCurrentRadioAccessTechnology?[serviceId] {
                        result = ("cell", self.simpleConnectionName(connectionType: radioAccessTechnology), nil)
                    } else {
                        result = ("cell", "unknown", nil)
                    }
                } else {
                    if let networkInfo = self.networkInfo, let serviceId = networkInfo.dataServiceIdentifier,
                       let radioAccessTechnology = networkInfo.serviceCurrentRadioAccessTechnology?[serviceId],
                       let carrier = networkInfo.serviceSubscriberCellularProviders?[serviceId] {
                        result = ("cell", self.simpleConnectionName(connectionType: radioAccessTechnology), carrier)
                    } else {
                        result = ("cell", "unknown", nil)
                    }
                }
            case .unavailable:
                result = ("unavailable", nil, nil)
            }
        }
        
        if Thread.isMainThread {
            fetchStatus()
        } else {
            DispatchQueue.main.async {
                fetchStatus()
            }
        }
        return result
    }

    func simpleConnectionName(connectionType: String) -> String {
        switch connectionType {
        case "CTRadioAccessTechnologyEdge":
            return "EDGE"
        case "CTRadioAccessTechnologyCDMA1x":
            return "CDMA"
        case "CTRadioAccessTechnologyGPRS":
            return "GPRS"
        case "CTRadioAccessTechnologyWCDMA":
            return "WCDMA"
        case "CTRadioAccessTechnologyHSDPA":
            return "HSDPA"
        case "CTRadioAccessTechnologyHSUPA":
            return "HSUPA"
        case "CTRadioAccessTechnologyCDMAEVDORev0":
            return "EVDO_0"
        case "CTRadioAccessTechnologyCDMAEVDORevA":
            return "EVDO_A"
        case "CTRadioAccessTechnologyCDMAEVDORevB":
            return "EVDO_B"
        case "CTRadioAccessTechnologyeHRPD":
            return "HRPD"
        case "CTRadioAccessTechnologyLTE":
            return "LTE"
        case "CTRadioAccessTechnologyNRNSA":
            return "NRNSA"
        case "CTRadioAccessTechnologyNR":
            return "NR"
        default:
            return "unknown"
        }
    }
}

#endif // os(iOS) && !targetEnvironment(macCatalyst)
