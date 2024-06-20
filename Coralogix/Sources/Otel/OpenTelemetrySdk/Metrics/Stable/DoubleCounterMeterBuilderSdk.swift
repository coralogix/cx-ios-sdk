//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public class DoubleCounterMeterBuilderSdk: DoubleCounterBuilder, InstrumentBuilder {
    var meterSharedState: StableMeterSharedState
    
    var meterProviderSharedState: MeterProviderSharedState
        
    let type: InstrumentType = .counter
    
    let valueType: InstrumentValueType = .double
    
    var instrumentName: String
    
    var description: String
    
    var unit: String
    
    init(meterProviderSharedState: MeterProviderSharedState,
         meterSharedState: StableMeterSharedState,
         name: String,
         description: String,
         unit: String) {
        self.meterProviderSharedState = meterProviderSharedState
        self.meterSharedState = meterSharedState
        self.unit = unit
        self.description = description
        self.instrumentName = name
    }
    
    public func build() -> DoubleCounter {
        buildSynchronousInstrument(DoubleCounterSdk.init)
    }
    
    public func buildWithCallback(_ callback: @escaping (ObservableDoubleMeasurement) -> Void)
        -> ObservableDoubleCounter {
        registerDoubleAsynchronousInstrument(type: .observableCounter, updater: callback)
    }
}
