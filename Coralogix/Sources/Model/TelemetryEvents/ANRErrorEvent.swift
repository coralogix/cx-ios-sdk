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
    var type: EventType { .error }
    let errorMessage: String
    let errorType: String
    /// Every thread as the hang was detected, main first, in the crash threads' wire shape.
    let threads: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        errorMessage: String = WireValues.anrErrorMessage.rawValue,
        errorType: String = WireValues.anrErrorType.rawValue,
        threads: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.errorMessage = errorMessage
        self.errorType = errorType
        self.threads = threads
    }

    func toOTelAttributes() -> [String: AttributeValue] {
        var attributes: [String: AttributeValue] = [
            Keys.eventType.rawValue:    .string(type.rawValue),
            Keys.errorMessage.rawValue: .string(errorMessage),
            Keys.errorType.rawValue:    .string(errorType),
        ]
        if let threads {
            attributes[Keys.threads.rawValue] = .string(threads)
        }
        return attributes
    }
}
