//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
// 

import Foundation
// 

public class SumAggregator  {

    public let isMonotonic : Bool
    
    init(instrumentDescriptor : InstrumentDescriptor) {
        isMonotonic = instrumentDescriptor.type == .histogram || instrumentDescriptor.type == .counter ||
        instrumentDescriptor.type == .observableCounter
    }
}
