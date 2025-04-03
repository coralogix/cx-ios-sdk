/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
// 

struct IntObserverMetricHandleSdk: IntObserverMetricHandle {
    public private(set) var aggregator = LastValueAggregator<Int>()

    func observe(value: Int) {
        aggregator.update(value: value)
    }
}
