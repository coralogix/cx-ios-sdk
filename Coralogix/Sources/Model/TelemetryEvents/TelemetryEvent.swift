//
//  TelemetryEvent.swift
//
//
//  Created by Coralogix DEV TEAM on 17/05/2026.
//

import Foundation
import CoralogixInternal

typealias EventType = CoralogixEventType

protocol TelemetryEvent: Codable {
    var id: UUID { get }
    var timestamp: Date { get }
    var type: EventType { get }

    // Every attribute key MUST come from `Keys.<case>.rawValue` — never a
    // string literal. The wire format (snake_case / camelCase mixing) lives
    // in `Keys.swift` and this adapter must stay in lockstep with it.
    func toOTelAttributes() -> [String: AttributeValue]
}
