/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */


import Foundation
import CoralogixInternal

class BoundRawCounterMetricSdkBase<T>: BoundRawCounterMetric<T> {
    internal var status : RecordStatus
    internal var statusLock = Lock()
    
    init(recordStatus: RecordStatus) {
        status = recordStatus
        super.init()
    }
    
    func checkpoint() {
    }
    
    func getMetrics() -> [MetricData] {
        Log.w("[Coralogix] BoundRawCounterMetricSdkBase.getMetrics() returned empty fallback — raw counter points dropped; subclass should override")
        return []
    }
    
}
