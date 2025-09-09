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
        var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.internalKey.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        self.addUserMetadata(to: &span)
        span.end()
    }
}
