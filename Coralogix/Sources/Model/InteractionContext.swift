//
//  InteractionContext.swift
//  
//
//  Created by Coralogix DEV TEAM on 04/08/2024.
//

import Foundation

struct InteractionContext {
    var elementId: String?
    var eventName: String?
    var attributes: [String: Any]?
    
    init(otel: SpanDataProtocol) {
        if let jsonString = otel.getAttribute(forKey: Keys.tapObject.rawValue) as? String,
           let tapObject = Helper.convertJsonStringToDict(jsonString: jsonString) {
            self.eventName = Keys.click.rawValue
            self.elementId = tapObject[Keys.tapName.rawValue] as? String ?? ""
            self.attributes = tapObject[Keys.attributes.rawValue] as? [String: Any] ?? nil
        }
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.elementId.rawValue] = self.elementId
        result[Keys.eventName.rawValue] = self.eventName
        result[Keys.attributes.rawValue] = self.attributes
        return result
    }
}
