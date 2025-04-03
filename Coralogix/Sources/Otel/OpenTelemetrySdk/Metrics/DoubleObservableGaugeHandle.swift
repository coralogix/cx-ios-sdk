/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
// 

struct DoubleObservableGaugeHandle: DoubleObserverMetricHandle {
    public private(set) var aggregator = MaxValueAggregator<Double>()

    func observe(value: Double) {
        aggregator.update(value: value)
    }
}
