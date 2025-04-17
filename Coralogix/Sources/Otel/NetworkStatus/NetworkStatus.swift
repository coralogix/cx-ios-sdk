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
        switch networkMonitor.getConnection() {
        case .wifi:
            return ("wifi", nil, nil)
        case .cellular:
            if #available(iOS 16.0, *) {
                if let networkInfo = self.networkInfo, let serviceId = networkInfo.dataServiceIdentifier {
                    if let radioAccessTechnology = networkInfo.serviceCurrentRadioAccessTechnology?[serviceId] {
                        // iOS 16+: CTServiceCarrier is now used
                        return ("cell", simpleConnectionName(connectionType: radioAccessTechnology), nil)
                    }
                }
            } else {
                if let networkInfo = self.networkInfo, let serviceId = networkInfo.dataServiceIdentifier {
                    if let radioAccessTechnology = networkInfo.serviceCurrentRadioAccessTechnology?[serviceId],
                       let carrier = networkInfo.serviceSubscriberCellularProviders?[serviceId] {
                        return ("cell", simpleConnectionName(connectionType: radioAccessTechnology), carrier)
                    }
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
