//
//  ANRErrorEvent.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import Foundation
import CoralogixInternal

// ANR (Application Not Responding) is delivered on the wire as an `error`
// event with a fixed `errorType` discriminator ("ANR"). Keeping it as its
// own struct — separate from ErrorEvent — gives middleware a clear hook
// without overloading ErrorEvent's larger field set.
struct ANRErrorEvent: TelemetryEvent {
    let id: UUID
    let timestamp: Date
    let type: EventType
    let errorMessage: String
    let errorType: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        errorMessage: String = "Application Not Responding",
        errorType: String = "ANR"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = .error
        self.errorMessage = errorMessage
        self.errorType = errorType
    }

    func toOTelAttributes() -> [String: AttributeValue] {
        return [
            Keys.eventType.rawValue:    .string(type.rawValue),
            Keys.errorMessage.rawValue: .string(errorMessage),
            Keys.errorType.rawValue:    .string(errorType),
        ]
    }
}
