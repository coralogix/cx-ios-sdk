//
//  InteractionEnums.swift
//
//
//  Created by Coralogix DEV TEAM on 05/02/2025.
//

import Foundation

/// The type of a recorded user interaction.
public enum InteractionEventName: String {
    case click  = "click"
    case scroll = "scroll"
    case swipe  = "swipe"
}

/// Direction of a scroll or swipe gesture.
public enum ScrollDirection: String {
    case up    = "up"
    case down  = "down"
    case left  = "left"
    case right = "right"
}
