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
    
    public func inject(span: any Span) {
        let (type, subtype, carrier) = netstat.status()
        // Set the connection type
        span.setAttribute(key: SemanticAttributes.networkConnectionType.rawValue, value: AttributeValue.string(type))
        
        // Set the connection subtype if available
        if let subtype: String = subtype {
            span.setAttribute(key: SemanticAttributes.networkConnectionSubtype.rawValue, value: AttributeValue.string(subtype))
        }
#if targetEnvironment(simulator)
        Log.w("Running in simulator, skipping carrier info.")
#else
        
        if #available(iOS 16.0, *) {
            // Carrier information is deprecated with no replacement in iOS 16 and above.
            // Skip setting carrier-related attributes.
            return
        } else {
            // iOS 15 and below: Handle carrier info using CTCarrier
            if let carrierInfo = carrier as? CTCarrier {
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
#endif
    }
}

#endif // os(iOS) && !targetEnvironment(macCatalyst)
