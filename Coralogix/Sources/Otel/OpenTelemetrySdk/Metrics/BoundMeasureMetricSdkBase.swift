/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoralogixInternal

class BoundMeasureMetricSdkBase<T>: BoundMeasureMetric<T> {
    override init() {
        super.init()
    }

    func getAggregator() -> Aggregator<T> {
        Log.w("[Coralogix] BoundMeasureMetricSdkBase.getAggregator() returned fallback no-op Aggregator — min/max/sum/count data dropped; subclass should override")
        return Aggregator<T>()
    }
}
