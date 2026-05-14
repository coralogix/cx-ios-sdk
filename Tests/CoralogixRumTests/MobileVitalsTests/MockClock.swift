//
//  MockClock.swift
//
//
//  Created by Coralogix DEV TEAM on 14/05/2026.
//

import Foundation
import CoralogixInternal

final class MockClock: CoralogixInternal.Clock {
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 0)) {
        self.current = start
    }

    func now() -> Date {
        current
    }

    func advance(by interval: TimeInterval) {
        current = current.addingTimeInterval(interval)
    }
}
