//
//  CXANRDetector.swift
//
//
//  Created by Tomer Har Yoffi on 27/08/2024.
//

import Foundation

class CXANRDetector {
    internal var timer: Timer?
    private var isMainThreadResponsive = true

    // Time interval to check for ANR (e.g., every 1 second)
    private let checkInterval: TimeInterval

    // Maximum allowed main thread block time (e.g., 5 seconds)
    private let maxBlockTime: TimeInterval

    private var lastCheckTimestamp: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    // ANR handling closure (useful for testing)
    var handleANRClosure: (() -> Void)?
    
    init(checkInterval: TimeInterval = 1.0, maxBlockTime: TimeInterval = 5.0) {
        self.checkInterval = checkInterval
        self.maxBlockTime = maxBlockTime
        self.lastCheckTimestamp = CFAbsoluteTimeGetCurrent()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(timeInterval: checkInterval, target: self, selector: #selector(checkForANR), userInfo: nil, repeats: true)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func checkForANR() {
        let currentTime = CFAbsoluteTimeGetCurrent()
        isMainThreadResponsive = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isMainThreadResponsive = true
            self.lastCheckTimestamp = currentTime
        }

        if !isMainThreadResponsive && (currentTime - lastCheckTimestamp) > maxBlockTime {
            handleANR()
        }
    }

    public func handleANR() {
        // ANR detected, handle it here (e.g., log, notify, etc.)
        handleANRClosure?()  // Call closure in test
        Log.d("[Metric] ANR detected: Main thread unresponsive for more than \(maxBlockTime) seconds")
        // send instrumentaion event
        NotificationCenter.default.post(name: .cxRumNotificationMetrics,
                                        object: CXMobileVitals(type: .anr, value: ""))
    }
}
