//
//  TimeIntervalExt.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation

extension TimeInterval {
    var seconds: Int {
        return Int(self.rounded())
    }

    var milliseconds: Int {
        return Int(self * 1_000)
    }
    
    var openTelemetryFormat: [UInt64] {
        guard self.isFinite && self >= 0 else {
            return [0, 0]
        }

        let (integerPart, fractionalPart) = modf(self)
        let seconds = UInt64(integerPart)
        let nanoseconds = UInt64((fractionalPart * 1_000_000_000).rounded())
        return [seconds, nanoseconds]
    }
    
    var openTelemetryMilliseconds: UInt64 {
        guard self.isFinite && self >= 0 else {
            return 0
        }
        return UInt64((self * 1_000).rounded())
    }
}
