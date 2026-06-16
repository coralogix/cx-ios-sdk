//
//  InternalContext.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 07/09/2025.
//

struct InternalContext {
    let eventName: String
    let data: [String: Any]

    func getDictionary() -> [String: Any] {
        var result: [String: Any] = [:]
        result[Keys.event.rawValue] = eventName
        result[Keys.data.rawValue] = data
        return result
    }
}
