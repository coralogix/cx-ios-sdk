//
//  ErrorEvent.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import Foundation
import CoralogixInternal

struct ErrorEvent: TelemetryEvent {
    let id: UUID
    let timestamp: Date
    let type: EventType
    let domain: String
    let code: Int?
    let errorMessage: String
    let isCrash: Bool
    let errorType: String?
    let arch: String?
    let buildId: String?
    let stackTraceType: String?

    // Encoded as JSON strings on the OTel span (matches what ErrorContext
    // expects when reading them back out via convertJsonStringToDict /
    // convertJsonStringToArray).
    let userInfoJson: String?
    let stackTraceJson: String?

    // NOTE: crash-path fields (exceptionType, crashTimestamp, processName,
    // applicationIdentifier, triggeredByThread, baseAddress, threads) are NOT
    // surfaced here. The crash wire shape differs significantly from a
    // hand-written error and the AC may surface that as a separate struct
    // alongside ANRErrorEvent. Keep this struct aligned with the writeError
    // emission path until the crash variant is specified.

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        domain: String,
        code: Int? = nil,
        errorMessage: String,
        isCrash: Bool = false,
        errorType: String? = nil,
        arch: String? = nil,
        buildId: String? = nil,
        stackTraceType: String? = nil,
        userInfoJson: String? = nil,
        stackTraceJson: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = .error
        self.domain = domain
        self.code = code
        self.errorMessage = errorMessage
        self.isCrash = isCrash
        self.errorType = errorType
        self.arch = arch
        self.buildId = buildId
        self.stackTraceType = stackTraceType
        self.userInfoJson = userInfoJson
        self.stackTraceJson = stackTraceJson
    }

    func toOTelAttributes() -> [String: AttributeValue] {
        var attrs: [String: AttributeValue] = [
            Keys.eventType.rawValue:    .string(type.rawValue),
            Keys.domain.rawValue:       .string(domain),
            Keys.errorMessage.rawValue: .string(errorMessage),
            Keys.isCrash.rawValue:      .bool(isCrash),
        ]
        if let code           { attrs[Keys.code.rawValue]           = .int(code) }
        if let errorType      { attrs[Keys.errorType.rawValue]      = .string(errorType) }
        if let arch           { attrs[Keys.arch.rawValue]           = .string(arch) }
        if let buildId        { attrs[Keys.buildId.rawValue]        = .string(buildId) }
        if let stackTraceType { attrs[Keys.stackTraceType.rawValue] = .string(stackTraceType) }
        if let userInfoJson   { attrs[Keys.userInfo.rawValue]       = .string(userInfoJson) }
        if let stackTraceJson { attrs[Keys.stackTrace.rawValue]     = .string(stackTraceJson) }
        return attrs
    }
}
