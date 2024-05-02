//
//  LogContext.swift
//  Elastiflix-iOS
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import OpenTelemetrySdk

struct LogContext {
    let message: String
    var data: [String: Any]?
    
    init(otel: SpanData) {
        self.message = otel.attributes[Keys.message.rawValue]?.description ?? ""
        let jsonString = otel.attributes[Keys.data.rawValue]?.description ?? ""

        if let data = Helper.convertJsonStringToDict(jsonString: jsonString) {
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
