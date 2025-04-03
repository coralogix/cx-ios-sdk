//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public class LongToDoubleExemplarReservoir: ExemplarReservoir {
    let reservoir: ExemplarReservoir
    
    public init(reservoir: ExemplarReservoir) {
        self.reservoir = reservoir
    }
    
    public override func collectAndReset(attribute: [String: AttributeValue]) -> [ExemplarData] {
        return reservoir.collectAndReset(attribute: attribute)
    }
    
    public override func offerDoubleMeasurement(value: Double, attributes: [String: AttributeValue]) {
        return reservoir.offerDoubleMeasurement(value: value, attributes: attributes)
    }
    
    public override func offerLongMeasurement(value: Int, attributes: [String: AttributeValue]) {
        return offerDoubleMeasurement(value: Double(value), attributes: attributes)
    }
}

