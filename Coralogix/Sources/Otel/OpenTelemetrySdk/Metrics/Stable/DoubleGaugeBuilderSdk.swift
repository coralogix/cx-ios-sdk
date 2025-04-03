//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
// 

import Foundation

public class DoubleGaugeBuilderSdk : DoubleGaugeBuilder, InstrumentBuilder {
    
    var meterProviderSharedState: MeterProviderSharedState
    
    var meterSharedState: StableMeterSharedState
    
    var type: InstrumentType = .observableGauge
    
    var valueType: InstrumentValueType = .double
    
    var description: String = ""
    
    var unit: String = ""
    
    var instrumentName: String
    
    
    init(meterProviderSharedState: inout MeterProviderSharedState, meterSharedState : inout StableMeterSharedState, name: String) {
        self.meterProviderSharedState = meterProviderSharedState
        self.meterSharedState = meterSharedState
        instrumentName = name
    }
    
    public func ofLongs() -> LongGaugeBuilder {
        swapBuilder(LongGaugeBuilderSdk.init)
    }
    
    public func buildWithCallback(_ callback: @escaping (ObservableDoubleMeasurement) -> Void) -> ObservableDoubleGauge {
        registerDoubleAsynchronousInstrument(type: type, updater: callback)
    }
}
