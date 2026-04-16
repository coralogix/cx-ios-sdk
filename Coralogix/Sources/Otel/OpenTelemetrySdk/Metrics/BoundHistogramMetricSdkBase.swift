/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoralogixInternal

class BoundHistogramMetricSdkBase<T>: BoundHistogramMetric<T> {
    override init(explicitBoundaries: Array<T>? = nil) {
        super.init(explicitBoundaries: explicitBoundaries)
    }

    func getAggregator() -> Aggregator<T> {
        Log.w("[Coralogix] BoundHistogramMetricSdkBase.getAggregator() returned fallback no-op Aggregator — histogram data dropped; subclass should override")
        return Aggregator<T>()
    }
}
