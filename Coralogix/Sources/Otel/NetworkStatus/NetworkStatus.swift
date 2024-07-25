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
        let networkInfo = CTTelephonyNetworkInfo()
        networkInfo = info
#endif
    }

    public func status() -> (String, String?, CTCarrier?) {
        switch networkMonitor.getConnection() {
        case .wifi:
            return ("wifi", nil, nil)
        case .cellular:
            if #available(iOS 13.0, *) {
                if let serviceId = self.networkInfo?.dataServiceIdentifier, let value = self.networkInfo?.serviceCurrentRadioAccessTechnology?[serviceId] {
                    if let dataServiceIdentifier = self.networkInfo?.dataServiceIdentifier {
                        return ("cell", simpleConnectionName(connectionType: value), self.networkInfo?.serviceSubscriberCellularProviders?[dataServiceIdentifier])
                    }
                }
            } else {
                if let radioType = self.networkInfo?.currentRadioAccessTechnology {
                    return ("cell", simpleConnectionName(connectionType: radioType), self.networkInfo?.subscriberCellularProvider)
                }
            }
            return ("cell", "unknown", nil)
        case .unavailable:
            return ("unavailable", nil, nil)
        }
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
