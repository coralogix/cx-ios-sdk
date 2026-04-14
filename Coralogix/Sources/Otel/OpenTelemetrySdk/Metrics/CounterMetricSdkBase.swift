/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoralogixInternal

class CounterMetricSdkBase<T>: CounterMetric {
    let bindUnbindLock = Lock()
    public private(set) var boundInstruments = [LabelSet: BoundCounterMetricSdkBase<T>]()
    let metricName: String

    init(name: String) {
        metricName = name
    }

    func add(value: T, labelset: LabelSet) {
        Log.w("[Coralogix] CounterMetricSdkBase.add(value:labelset:) called on base class for metric '\(metricName)' — update dropped; subclass should override")
    }

    func add(value: T, labels: [String: String]) {
        Log.w("[Coralogix] CounterMetricSdkBase.add(value:labels:) called on base class for metric '\(metricName)' — update dropped; subclass should override")
    }

    func bind(labelset: LabelSet) -> BoundCounterMetric<T> {
        return bind(labelset: labelset, isShortLived: false)
    }

    func bind(labels: [String: String]) -> BoundCounterMetric<T> {
        return bind(labelset: LabelSet(labels: labels), isShortLived: false)
    }

    internal func bind(labelset: LabelSet, isShortLived: Bool) -> BoundCounterMetric<T> {
        var boundInstrument: BoundCounterMetricSdkBase<T>?
        bindUnbindLock.withLockVoid {
            boundInstrument = boundInstruments[labelset]

            if boundInstrument == nil {
                let status = isShortLived ? RecordStatus.updatePending : RecordStatus.bound
                boundInstrument = createMetric(recordStatus: status)
                boundInstruments[labelset] = boundInstrument
            }
        }

        boundInstrument!.statusLock.withLockVoid {
            switch boundInstrument!.status {
            case .noPendingUpdate:
                boundInstrument!.status = .updatePending
                break
            case .candidateForRemoval:
                bindUnbindLock.withLockVoid {
                    boundInstrument!.status = .updatePending

                    if boundInstruments[labelset] == nil {
                        boundInstruments[labelset] = boundInstrument!
                    }
                }
            case .bound, .updatePending:
                break
            }
        }

        return boundInstrument!
    }

    internal func unBind(labelSet: LabelSet) {
        bindUnbindLock.withLockVoid {
            if let boundInstrument = boundInstruments[labelSet] {
                boundInstrument.statusLock.withLockVoid {
                    if boundInstrument.status == .candidateForRemoval {
                        boundInstruments[labelSet] = nil
                    }
                }
            }
        }
    }

    func createMetric(recordStatus: RecordStatus) -> BoundCounterMetricSdkBase<T> {
        Log.w("[Coralogix] CounterMetricSdkBase.createMetric(recordStatus:) returned fallback for metric '\(metricName)' — subclass should override")
        return BoundCounterMetricSdkBase<T>(recordStatus: recordStatus)
    }
}
