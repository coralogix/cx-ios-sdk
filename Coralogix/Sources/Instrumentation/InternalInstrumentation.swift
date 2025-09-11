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
        var span = makeSpan(event: .internalKey, source: .console, severity: .info)
        span.end()
    }
}
