//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
// 

import Foundation

public class EmptyMetricStorage : SynchronousMetricStorageProtocol  {
    public func recordLong(value: Int, attributes: [String : AttributeValue]) {
    }
    
    public func recordDouble(value: Double, attributes: [String : AttributeValue]) {
    }
    
    public static var instance = EmptyMetricStorage()
    
    public var metricDescriptor: MetricDescriptor = MetricDescriptor(name: "", description: "", unit: "")
    
    public func collect(resource: Resource, scope: InstrumentationScopeInfo, startEpochNanos: UInt64, epochNanos: UInt64) -> StableMetricData {
        StableMetricData.empty
    }
    
    public func isEmpty() -> Bool {
        true
    }
}
