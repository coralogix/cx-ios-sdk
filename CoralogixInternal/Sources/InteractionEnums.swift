//
//  InteractionEnums.swift
//
//
//  Created by Coralogix DEV TEAM on 05/02/2025.
//

import Foundation

/// The type of a recorded user interaction.
public enum InteractionEventName: String {
    case click
    case scroll
    case swipe // Reserved for future use (UISwipeGestureRecognizer / SwiftUI DragGesture)
}

/// Direction of a scroll or swipe gesture.
public enum ScrollDirection: String {
    case up
    case down
    case left
    case right
}
