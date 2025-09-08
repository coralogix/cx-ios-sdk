//
//  InternalContext.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 07/09/2025.
//

struct InternalContext {
    let eventName: String
    let options: CoralogixExporterOptions

    func getDictionary() -> [String: Any] {
        var result: [String: Any] = [:]
        result[Keys.event.rawValue] = Keys.initKey.rawValue
        result[Keys.data.rawValue] = options.getInitData()
        return result
    }
}
