//
//  File.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 24/06/2025.
//

import Foundation

internal struct TraceParentInHeader {
    var enable: Bool = false
    var allowedTracingUrls: [String]? = nil
    
    init(params: [String : Any]?) {
        guard let params = params else {
            Log.e("[TraceParentInHeader missing parmas]")
            return
        }
        enable = params["enable"] as? Bool ?? false
        let options = params["options"] as? [String: Any]
        allowedTracingUrls = options?["allowedTracingUrls"] as? [String]
    }
}
