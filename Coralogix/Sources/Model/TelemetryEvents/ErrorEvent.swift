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
    var type: EventType { .error }
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

    /// Ergonomic factory that accepts unencoded `userInfo` / `stackTrace`
    /// dictionaries and performs the JSON encoding internally. Prefer this
    /// over the raw `init` — it moves the "must be valid JSON" contract from
    /// the call site into the model, eliminating a class of silent failures
    /// (`ErrorContext` drops malformed JSON without surfacing the error).
    static func make(
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
        userInfo: [String: Any]? = nil,
        stackTrace: [[String: Any]]? = nil
    ) -> ErrorEvent {
        let userInfoJson = userInfo.map { Helper.convertDictionaryToJsonString(dict: $0) }
        let stackTraceJson = stackTrace.flatMap { frames -> String? in
            guard JSONSerialization.isValidJSONObject(frames),
                  let data = try? JSONSerialization.data(withJSONObject: frames, options: []) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        return ErrorEvent(
            id: id,
            timestamp: timestamp,
            domain: domain,
            code: code,
            errorMessage: errorMessage,
            isCrash: isCrash,
            errorType: errorType,
            arch: arch,
            buildId: buildId,
            stackTraceType: stackTraceType,
            userInfoJson: userInfoJson,
            stackTraceJson: stackTraceJson
        )
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
