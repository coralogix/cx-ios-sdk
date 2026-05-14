//
//  Clock.swift
//
//
//  Created by Coralogix DEV TEAM on 14/05/2026.
//

import Foundation

/// Abstraction over wall-clock time so time-dependent code can be exercised
/// deterministically in tests without `Thread.sleep`.
public protocol Clock {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}
