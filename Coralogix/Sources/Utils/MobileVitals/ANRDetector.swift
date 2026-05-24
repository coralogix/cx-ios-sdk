//
//  ANRDetector.swift
//
//
//  Created by Coralogix DEV TEAM on 27/08/2024.
//

import Foundation
import CoralogixInternal

internal class ANRDetector {
    internal var timer: Timer?
    private var isMainThreadResponsive = true

    // Time interval to check for ANR (e.g., every 1 second)
    let checkInterval: TimeInterval

    // Maximum allowed main thread block time (e.g., 5 seconds)
    let maxBlockTime: TimeInterval

    private let clock: CoralogixInternal.Clock
    private var lastCheckTimestamp: Date

    // ANR handling closure (useful for testing)
    var handleANRClosure: (() -> Void)?

    /// Injected typed event sink (CX-40573 / CX-43340). When set,
    /// `handleANR()` reports the ANR directly through this protocol instead
    /// of routing through `MetricsManager.handleANREvent` via the legacy
    /// `handleANRClosure`. Production wires `SpanEventReporter`; tests
    /// inject a recorder. nil falls back to the closure path for backward
    /// compatibility (closure removal is out of scope per CX-43340; covered by 1.5b).
    let eventReporter: EventReporter?

    init(checkInterval: TimeInterval = 1.0,
         maxBlockTime: TimeInterval = 5.0,
         clock: CoralogixInternal.Clock = SystemClock(),
         eventReporter: EventReporter? = nil) {
        self.checkInterval = checkInterval
        self.maxBlockTime = maxBlockTime
        self.clock = clock
        self.lastCheckTimestamp = clock.now()
        self.eventReporter = eventReporter
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(timeInterval: checkInterval, target: self, selector: #selector(checkForANR), userInfo: nil, repeats: true)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    @objc internal func checkForANR() {
        let currentTime = clock.now()
        isMainThreadResponsive = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isMainThreadResponsive = true
            self.lastCheckTimestamp = currentTime
        }

        if !isMainThreadResponsive && currentTime.timeIntervalSince(lastCheckTimestamp) > maxBlockTime {
            handleANR()
        }
    }

    public func handleANR() {
        let duration = clock.now().timeIntervalSince(lastCheckTimestamp)
        Log.d("[Metric] ANR detected: Main thread unresponsive for \(String(format: "%.2f", duration)) seconds")

        if let eventReporter = eventReporter {
            let event = ANRErrorEvent(
                errorMessage: WireValues.anrErrorMessage.rawValue,
                errorType: WireValues.anrErrorType.rawValue
            )
            eventReporter.report(event)
            return
        }
        handleANRClosure?()
    }
}
