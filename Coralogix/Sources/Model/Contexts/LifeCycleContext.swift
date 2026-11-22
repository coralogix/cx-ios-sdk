//
//  LifeCycleContext.swift
//
//
//  Created by Coralogix DEV TEAM on 17/11/2024.
//

import Foundation
import CoralogixInternal

struct LifeCycleContext {
    let lifeCycleType: String
    
    init(otel: SpanDataProtocol) {
        self.lifeCycleType = otel.getAttribute(forKey: Keys.type.rawValue) as? String ?? ""
    }
    
    /// The life-cycle event sent on entering the background: it carries a forced snapshot and
    /// skips the hybrid beforeSend round trip, so both checks must agree on what it is.
    static func isBackgroundEvent(type: CoralogixEventType?, lifeCycleName: String?) -> Bool {
        type == .lifeCycle && lifeCycleName == Keys.appDidEnterBackgroundNotification.rawValue
    }

    func getLifeCycleDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.eventName.rawValue] = self.lifeCycleType
        return result
    }
}
