/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */


import Foundation
import CoralogixInternal

class BoundRawHistogramMetricSdkBase<T> : BoundRawHistogramMetric<T> {
    internal var status : RecordStatus
    internal var statusLock = Lock()
    
    init(recordStatus: RecordStatus) {
        status = recordStatus
        super.init()
    }
    
    func checkpoint() {
    }
    
    func getMetrics() -> [MetricData] {
        Log.w("[Coralogix] BoundRawHistogramMetricSdkBase.getMetrics() returned empty fallback — raw histogram points dropped; subclass should override")
        return []
    }
}
