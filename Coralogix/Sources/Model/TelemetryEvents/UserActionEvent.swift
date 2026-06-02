//
//  UserActionEvent.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import Foundation
import CoralogixInternal

struct UserActionEvent: TelemetryEvent {
    let id: UUID
    let timestamp: Date
    var type: EventType { .userInteraction }
    let eventName: InteractionEventName
    let targetElement: String
    let elementClasses: String?
    let elementId: String?
    let targetElementInnerText: String?
    let scrollDirection: ScrollDirection?
    /// Free-form user-supplied sub-dict forwarded from hybrid bridges
    /// (Flutter/RN). Heterogeneous values are modelled via `JSONValue`.
    let attributes: [String: JSONValue]?

    // NOTE: `positionX` / `positionY` (touch coordinates) are intentionally
    // not surfaced. `UserActionsInstrumentation.validateHybridInteraction`
    // writes them into the tap_object dict, but `InteractionContext` never
    // reads them back — they're a pre-existing gap in the iOS extraction
    // path and surfacing them here without fixing the extractor would imply
    // a wire contract that isn't actually delivered.

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventName: InteractionEventName,
        targetElement: String,
        elementClasses: String? = nil,
        elementId: String? = nil,
        targetElementInnerText: String? = nil,
        scrollDirection: ScrollDirection? = nil,
        attributes: [String: JSONValue]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventName = eventName
        self.targetElement = targetElement
        self.elementClasses = elementClasses
        self.elementId = elementId
        self.targetElementInnerText = targetElementInnerText
        self.scrollDirection = scrollDirection
        self.attributes = attributes
    }

    func toOTelAttributes() -> [String: AttributeValue] {
        var tapObject: [String: Any] = [
            Keys.eventName.rawValue: eventName.rawValue,
            Keys.targetElement.rawValue: targetElement,
        ]
        if let v = elementClasses         { tapObject[Keys.elementClasses.rawValue] = v }
        if let v = elementId              { tapObject[Keys.elementId.rawValue] = v }
        if let v = targetElementInnerText { tapObject[Keys.targetElementInnerText.rawValue] = v }
        if let v = scrollDirection        { tapObject[Keys.scrollDirection.rawValue] = v.rawValue }
        if let v = attributes             { tapObject[Keys.attributes.rawValue] = v.mapValues { $0.toAny() } }

        var attrs: [String: AttributeValue] = [
            Keys.eventType.rawValue: .string(type.rawValue),
        ]
        if let json = Helper.jsonAttributeString(dict: tapObject) {
            attrs[Keys.tapObject.rawValue] = .string(json)
        }
        return attrs
    }
}
