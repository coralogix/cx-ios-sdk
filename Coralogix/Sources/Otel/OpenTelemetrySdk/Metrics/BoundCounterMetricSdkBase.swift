/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoralogixInternal

class BoundCounterMetricSdkBase<T>: BoundCounterMetric<T> {
    internal var status: RecordStatus
    internal let statusLock = Lock()

    init(recordStatus: RecordStatus) {
        status = recordStatus
        super.init()
    }

    func getAggregator() -> Aggregator<T> {
        Log.w("[Coralogix] BoundCounterMetricSdkBase.getAggregator() returned fallback no-op Aggregator — subclass should override")
        return Aggregator<T>()
    }
}
