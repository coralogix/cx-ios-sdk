/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if os(iOS) && !targetEnvironment(macCatalyst)

import CoreTelephony
import Foundation

public protocol NetworkStatusProtocol {
    var networkMonitor: NetworkMonitorProtocol { get }
    /// Retrieves the network status, including connection type and carrier information.
    /// - Returns: A tuple containing the connection type as a string and carrier information as `Any?`.
    ///            The carrier information is either a `CTCarrier` (iOS 15 and below) or `nil` (iOS 16 and above).
    func getStatus() -> (String, Any?)
}
#endif // os(iOS) && !targetEnvironment(macCatalyst)
