//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
// 

import Foundation
// 


public struct Measurement {
    public private(set) var startEpochNano : UInt64
    public private(set) var epochNano : UInt64
    public private(set) var hasLongValue: Bool
    public private(set) var longValue: Int
    public private(set) var doubleValue : Double
    public private(set) var hasDoubleValue: Bool
    public private(set) var attributes : [String: AttributeValue]
    
    internal init(startEpochNano: UInt64, epochNano: UInt64, hasLongValue: Bool, longValue: Int, doubleValue: Double, hasDoubleValue: Bool, attributes: [String : AttributeValue]) {
        self.startEpochNano = startEpochNano
        self.epochNano = epochNano
        self.hasLongValue = hasLongValue
        self.longValue = longValue
        self.doubleValue = doubleValue
        self.hasDoubleValue = hasDoubleValue
        self.attributes = attributes
    }
    
    public static func longMeasurement(startEpochNano : UInt64, endEpochNano : UInt64, value: Int, attributes: [String: AttributeValue]) -> Measurement {
        Measurement(startEpochNano: startEpochNano, epochNano: endEpochNano, hasLongValue: true, longValue: value, doubleValue: 0.0, hasDoubleValue: false, attributes: attributes)
    }
    public static func doubleMeasurement(startEpochNano : UInt64, endEpochNano : UInt64, value: Double, attributes: [String: AttributeValue]) -> Measurement {
        Measurement(startEpochNano: startEpochNano, epochNano: endEpochNano, hasLongValue: false, longValue: 0, doubleValue: value, hasDoubleValue: true, attributes: attributes)
    }
}
