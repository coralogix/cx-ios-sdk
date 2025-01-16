//
//  TimeIntervalExt.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation

public extension TimeInterval {
    public var seconds: Int {
        return Int(self.rounded())
    }

    public var milliseconds: Int {
        return Int(self * 1_000)
    }
    
    public var openTelemetryFormat: [UInt64] {
        let (integerPart, fractionalPart) = modf(self)
        return [UInt64(integerPart), UInt64(fractionalPart * 1_000_000_000)]
    }
}
