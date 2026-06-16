//
//  InternalInstrumentation.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 08/09/2025.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    internal func createInitSpan() {
        let span = makeSpan(event: .internalKey, source: .console, severity: .info)
        span.end()
    }

    /// Emits the session-replay init log (CX-44984). The snapshot rides on the span as a JSON
    /// string and is decoded back into `internal_context` in `CxRumBuilder.buildInternalContext`.
    internal func createSessionReplayInitSpan(snapshot: [String: Any]) {
        var span = makeSpan(event: .internalKey, source: .console, severity: .info)
        span.setAttribute(key: Keys.internalEventType.rawValue, value: Keys.sessionReplayInit.rawValue)
        span.setAttribute(key: Keys.internalEventData.rawValue,
                          value: Helper.convertDictionaryToJsonString(dict: snapshot))
        span.end()
    }
}
