//
//  OtlpSpan+EventType.swift
//  DemoApp
//
//  Convenience accessor used by demo screens that capture spans through the
//  tracesExporter callback. The Coralogix `event_type` is a string attribute
//  on every emitted span; surfacing it as a property keeps capture-display
//  code readable.
//

import Coralogix
import CoralogixInternal

extension OtlpSpan {
    /// The `event_type` attribute Coralogix tags every span with, when present.
    var eventType: String? {
        guard let kv = attributes.first(where: { $0.key == CoralogixInternal.Keys.eventType.rawValue }) else { return nil }
        if case .stringValue(let value) = kv.value { return value }
        return nil
    }
}
