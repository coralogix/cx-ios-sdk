//
//  TraceParentInHeader.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 24/06/2025.
//

import Foundation
import CoralogixInternal

internal struct TraceParentInHeader {
    var enable: Bool = false
    var allowedTracingUrls: [String]?
    
    init(params: [String: Any]?) {
        guard let params = params else {
            Log.e("[TraceParentInHeader missing params]")
            return
        }
        // Accept both "enable" (native) and "enabled" (React Native bridge) for compatibility
        enable = params[Keys.enable.rawValue] as? Bool ?? params["enabled"] as? Bool ?? false
        let options = params[Keys.options.rawValue] as? [String: Any]
        allowedTracingUrls = options?[Keys.allowedTracingUrls.rawValue] as? [String]
    }
}
