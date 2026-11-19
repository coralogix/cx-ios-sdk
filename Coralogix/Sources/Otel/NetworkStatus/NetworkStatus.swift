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

    // Telephony state is snapshotted here so status() can run on any thread: reading
    // CTTelephonyNetworkInfo concurrently from several threads crashes, and hopping to
    // the main thread made off-main callers report "unavailable".
    private let lock = NSLock()
    private let refreshLock = NSLock()
    private var cachedServiceId: String?
    private var cachedRadioTech: [String: String]?
    private var cachedProviders: [String: CTCarrier]?
    private var delegateProxy: NetworkInfoDelegateProxy?
    private var radioTechObserver: NSObjectProtocol?

    public convenience init() throws {
        self.init(with: try NetworkMonitor())
    }

    public convenience init(with monitor: NetworkMonitorProtocol) {
#if targetEnvironment(simulator)
        self.init(with: monitor, networkInfo: nil)
#else
        self.init(with: monitor, networkInfo: CTTelephonyNetworkInfo())
#endif
    }

    init(with monitor: NetworkMonitorProtocol, networkInfo: CTTelephonyNetworkInfo?) {
        networkMonitor = monitor
        self.networkInfo = networkInfo
        refreshCachedState()
        guard let networkInfo else { return }
        let proxy = NetworkInfoDelegateProxy { [weak self] in self?.refreshCachedState() }
        networkInfo.delegate = proxy
        delegateProxy = proxy
        // The delegate reports only data-service switches; radio changes arrive as a notification.
        radioTechObserver = NotificationCenter.default.addObserver(
            forName: .CTServiceRadioAccessTechnologyDidChange, object: nil, queue: nil
        ) { [weak self] _ in self?.refreshCachedState() }
    }

    deinit {
        if let radioTechObserver {
            NotificationCenter.default.removeObserver(radioTechObserver)
        }
    }

    public func status() -> (String, String?, Any?) {
        switch networkMonitor.getConnection() {
        case .wifi:
            return ("wifi", nil, nil)
        case .unavailable:
            return ("unavailable", nil, nil)
        case .cellular:
            lock.lock()
            let serviceId = cachedServiceId
            let radioTech = cachedRadioTech
            let providers = cachedProviders
            lock.unlock()

            guard let serviceId, let technology = radioTech?[serviceId] else {
                return ("cell", "unknown", nil)
            }
            if #available(iOS 16.0, *) {
                return ("cell", simpleConnectionName(connectionType: technology), nil)
            }
            guard let carrier = providers?[serviceId] else {
                return ("cell", "unknown", nil)
            }
            return ("cell", simpleConnectionName(connectionType: technology), carrier)
        }
    }

    // Refreshes are serialised: the delegate and the radio notification arrive together on
    // CoreTelephony's queues, and two refreshes reading networkInfo at once is the crash this
    // class avoids. Serialising also keeps an older snapshot from landing after a newer one.
    // The cache lock is a separate one so status() never waits on a CoreTelephony read.
    private func refreshCachedState() {
        refreshLock.lock()
        defer { refreshLock.unlock() }
        let serviceId = networkInfo?.dataServiceIdentifier
        let radioTech = networkInfo?.serviceCurrentRadioAccessTechnology
        let providers = Self.cellularProviders(of: networkInfo)
        lock.lock()
        cachedServiceId = serviceId
        cachedRadioTech = radioTech
        cachedProviders = providers
        lock.unlock()
    }

    // The carrier is reported only before iOS 16, where Apple stopped returning real values.
    private static func cellularProviders(of networkInfo: CTTelephonyNetworkInfo?) -> [String: CTCarrier]? {
        if #available(iOS 16.0, *) { return nil }
        return networkInfo?.serviceSubscriberCellularProviders
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

private final class NetworkInfoDelegateProxy: NSObject, CTTelephonyNetworkInfoDelegate {
    private let onUpdate: () -> Void

    init(onUpdate: @escaping () -> Void) {
        self.onUpdate = onUpdate
    }

    func dataServiceIdentifierDidChange(_ identifier: String) {
        onUpdate()
    }
}

#endif // os(iOS) && !targetEnvironment(macCatalyst)
