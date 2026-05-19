//
//  MobileVitalsEvent.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import Foundation
import CoralogixInternal

struct MobileVitalsEvent: TelemetryEvent {
    let id: UUID
    let timestamp: Date
    var type: EventType { .mobileVitals }
    // Payload travels as a JSON-encoded string under `Keys.mobileVitalsType`
    // (camelCase on the wire — see Keys.swift) and is parsed back into a
    // dict on the exporter side. Holding the encoded string keeps the
    // struct honest about what hits the wire.
    let mobileVitalsType: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mobileVitalsType: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mobileVitalsType = mobileVitalsType
    }

    func toOTelAttributes() -> [String: AttributeValue] {
        return [
            Keys.eventType.rawValue: .string(type.rawValue),
            Keys.mobileVitalsType.rawValue: .string(mobileVitalsType),
        ]
    }
}
