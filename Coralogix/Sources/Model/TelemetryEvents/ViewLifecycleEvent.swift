//
//  ViewLifecycleEvent.swift
//
//
//  Created by Coralogix DEV TEAM on 17/05/2026.
//

import Foundation
import CoralogixInternal

struct ViewLifecycleEvent: TelemetryEvent {
    let id: UUID
    let timestamp: Date
    let type: EventType
    let lifeCycleType: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        lifeCycleType: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = .lifeCycle
        self.lifeCycleType = lifeCycleType
    }

    func toOTelAttributes() -> [String: AttributeValue] {
        return [
            Keys.eventType.rawValue: .string(type.rawValue),
            Keys.type.rawValue: .string(lifeCycleType),
        ]
    }
}
