//
//  CXANRDetector.swift
//
//
//  Created by Tomer Har Yoffi on 27/08/2024.
//

import Foundation

class CXANRDetector {
    private var timer: Timer?
    private var isMainThreadResponsive = true

    // Time interval to check for ANR (e.g., every 1 second)
    private let checkInterval: TimeInterval = 1.0

    // Maximum allowed main thread block time (e.g., 5 seconds)
    private let maxBlockTime: TimeInterval = 5.0

    private var lastCheckTimestamp: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

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

    private func handleANR() {
        // ANR detected, handle it here (e.g., log, notify, etc.)
        Log.d("ANR detected: Main thread unresponsive for more than \(maxBlockTime) seconds")
    }
}
