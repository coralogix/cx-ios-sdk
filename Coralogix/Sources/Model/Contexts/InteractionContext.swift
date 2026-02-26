//
//  InteractionContext.swift
//
//
//  Created by Coralogix DEV TEAM on 04/08/2024.
//

import Foundation
import CoralogixInternal

struct InteractionContext {
    var eventName: InteractionEventName // .click | .scroll | .swipe
    var elementClasses: String?          // UIKit class name — any class is valid, so stored as String
    var elementId: String?              // accessibilityIdentifier, or nil
    var targetElementInnerText: String? // visible text / accessibilityLabel, or nil
    var scrollDirection: ScrollDirection? // .up / .down / .left / .right — nil for tap
    var targetElement: String          // resolveTargetName result, or class name fallback
    var attributes: [String: Any]?

    init(otel: SpanDataProtocol) {
        guard let jsonString = otel.getAttribute(forKey: Keys.tapObject.rawValue) as? String,
              let tapObject = Helper.convertJsonStringToDict(jsonString: jsonString) else {
            eventName     = .click
            targetElement = ""
            return
        }

        if let nameStr = tapObject[Keys.eventName.rawValue] as? String {
            if let parsed = InteractionEventName(rawValue: nameStr) {
                eventName = parsed
            } else {
                Log.w("InteractionContext: unknown event_name '\(nameStr)' — defaulting to .click")
                eventName = .click
            }
        } else {
            eventName = .click
        }

        elementClasses = tapObject[Keys.elementClasses.rawValue] as? String

        elementId = tapObject[Keys.elementId.rawValue] as? String

        targetElementInnerText = tapObject[Keys.targetElementInnerText.rawValue] as? String

        if let dirStr = tapObject[Keys.scrollDirection.rawValue] as? String {
            if let parsed = ScrollDirection(rawValue: dirStr) {
                scrollDirection = parsed
            } else {
                Log.w("InteractionContext: unknown scroll_direction '\(dirStr)' — field omitted")
            }
        }

        targetElement = tapObject[Keys.targetElement.rawValue] as? String ?? ""
        attributes    = tapObject[Keys.attributes.rawValue] as? [String: Any]
    }

    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.eventName.rawValue]    = eventName.rawValue
        result[Keys.targetElement.rawValue] = targetElement

        if let v = elementClasses         { result[Keys.elementClasses.rawValue] = v }
        if let v = elementId              { result[Keys.elementId.rawValue] = v }
        if let v = targetElementInnerText { result[Keys.targetElementInnerText.rawValue] = v }
        if let v = scrollDirection        { result[Keys.scrollDirection.rawValue] = v.rawValue }
        if let v = attributes             { result[Keys.attributes.rawValue] = v }

        return result
    }
}
