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

    private var lastCheckTimestamp: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    // ANR handling closure (useful for testing)
    var handleANRClosure: (([String: Any]) -> Void)?
    
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
        let anr = [
            Keys.anr.rawValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.anr.stringValue
            ]
        ]
        
        handleANRClosure?(anr)  // Call closure in test
        Log.d("[Metric] ANR detected: Main thread unresponsive for more than \(maxBlockTime) seconds")
    }
}
