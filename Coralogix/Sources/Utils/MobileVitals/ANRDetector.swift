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

    init(checkInterval: TimeInterval = 1.0, maxBlockTime: TimeInterval = 5.0, clock: CoralogixInternal.Clock = SystemClock()) {
        self.checkInterval = checkInterval
        self.maxBlockTime = maxBlockTime
        self.clock = clock
        self.lastCheckTimestamp = clock.now()
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
        handleANRClosure?()

        let duration = clock.now().timeIntervalSince(lastCheckTimestamp)
        Log.d("[Metric] ANR detected: Main thread unresponsive for \(String(format: "%.2f", duration)) seconds")
    }
}
