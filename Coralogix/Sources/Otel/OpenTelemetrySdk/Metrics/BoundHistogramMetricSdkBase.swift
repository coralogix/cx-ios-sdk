/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
// 

class BoundHistogramMetricSdkBase<T>: BoundHistogramMetric<T> {
    override init(explicitBoundaries: Array<T>? = nil) {
        super.init(explicitBoundaries: explicitBoundaries)
    }

    func getAggregator() -> Aggregator<T> {
        fatalError()
    }
}
