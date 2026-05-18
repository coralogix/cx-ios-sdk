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
    let type: EventType
    let eventName: InteractionEventName
    let targetElement: String
    let elementClasses: String?
    let elementId: String?
    let targetElementInnerText: String?
    let scrollDirection: ScrollDirection?

    // NOTE: the wire format carries an optional free-form `attributes` sub-dict
    // (heterogeneous user-supplied values). Modelling that requires a shared
    // JSONValue helper that NetworkRequestEvent will also need; deferred to
    // the slice that introduces it. Until then, this struct covers the
    // structured fields surfaced by InteractionContext.

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventName: InteractionEventName,
        targetElement: String,
        elementClasses: String? = nil,
        elementId: String? = nil,
        targetElementInnerText: String? = nil,
        scrollDirection: ScrollDirection? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = .userInteraction
        self.eventName = eventName
        self.targetElement = targetElement
        self.elementClasses = elementClasses
        self.elementId = elementId
        self.targetElementInnerText = targetElementInnerText
        self.scrollDirection = scrollDirection
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

        let json = Helper.convertDictionaryToJsonString(dict: tapObject)
        return [
            Keys.eventType.rawValue: .string(type.rawValue),
            Keys.tapObject.rawValue: .string(json),
        ]
    }
}
