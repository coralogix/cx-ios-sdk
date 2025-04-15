//
//  LogContext.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import CoralogixInternal

struct LogContext {
    let message: String
    var data: [String: Any]?
    
    init(otel: SpanDataProtocol) {
        self.message = otel.getAttribute(forKey: Keys.message.rawValue) as? String ?? ""
    
        if let jsonString = otel.getAttribute(forKey: Keys.data.rawValue) as? String,
            let data = Helper.convertJsonStringToDict(jsonString: jsonString) {
            self.data = data
        }
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.message.rawValue] = self.message
        if let data = self.data {
            result[Keys.data.rawValue] = data
        }
        return result
    }
}
