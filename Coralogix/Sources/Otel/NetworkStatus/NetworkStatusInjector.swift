/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if os(iOS) && !targetEnvironment(macCatalyst)

import CoreTelephony
import Foundation
import Network

public class NetworkStatusInjector {
    private var netstat: NetworkStatusClass

    public init(netstat: NetworkStatusClass) {
        self.netstat = netstat
    }

    public func inject(span: Span) {
        let (type, subtype, carrier) = netstat.status()
      span.setAttribute(key: SemanticAttributes.networkConnectionType.rawValue, value: AttributeValue.string(type))

        if let subtype: String = subtype {
          span.setAttribute(key: SemanticAttributes.networkConnectionSubtype.rawValue, value: AttributeValue.string(subtype))
        }

        if let carrierInfo: CTCarrier = carrier {
            if let carrierName = carrierInfo.carrierName {
              span.setAttribute(key: SemanticAttributes.networkCarrierName.rawValue, value: AttributeValue.string(carrierName))
            }

            if let isoCountryCode = carrierInfo.isoCountryCode {
              span.setAttribute(key: SemanticAttributes.networkCarrierIcc.rawValue, value: AttributeValue.string(isoCountryCode))
            }

            if let mobileCountryCode = carrierInfo.mobileCountryCode {
              span.setAttribute(key: SemanticAttributes.networkCarrierMcc.rawValue, value: AttributeValue.string(mobileCountryCode))
            }

            if let mobileNetworkCode = carrierInfo.mobileNetworkCode {
              span.setAttribute(key: SemanticAttributes.networkCarrierMnc.rawValue, value: AttributeValue.string(mobileNetworkCode))
            }
        }
    }
}

#endif // os(iOS) && !targetEnvironment(macCatalyst)
