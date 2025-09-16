//
//  ColdDetector.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 15/09/2025.
//

import Foundation
import UIKit

final class ColdDetector {
    var launchStartTime: CFAbsoluteTime?
    var launchEndTime: CFAbsoluteTime?
    var handleColdClosure: (([String: Any]) -> Void)?

    func startMonitoring() {
        self.launchStartTime = CFAbsoluteTimeGetCurrent()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.handleNotification(notification:)),
                                               name: .cxViewDidAppear,
                                               object: nil)
    }
    
    @objc func handleNotification(notification: Notification) {
        if let metrics = notification.object as? [String: Any] {
            if let launchStartTime = self.launchStartTime,
               let launchEndTime = metrics[MobileVitalsType.cold.stringValue] as? CFAbsoluteTime,
               self.launchEndTime == nil {
                self.launchEndTime = launchEndTime
                let epochStartTime = Helper.convertCFAbsoluteTimeToEpoch(launchStartTime)
                let epochEndTime = Helper.convertCFAbsoluteTimeToEpoch(launchEndTime)
                let millisecondsRounded = self.calculateTime(start: epochStartTime, stop: epochEndTime)

//              Log.d("[COLD DEBUG] cold start = \(millisecondsRounded) ms")
                
                let cold = [
                    MobileVitalsType.cold.stringValue: [
                        Keys.mobileVitalsUnits.rawValue: MeasurementUnits.milliseconds.stringValue,
                        Keys.value.rawValue: millisecondsRounded
                    ]
                ]
                self.handleColdClosure?(cold)
            }
        }
    }
    
    func calculateTime(start: Double, stop: Double) -> Double {
        return max(0, stop - start)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .cxViewDidAppear, object: nil)
        self.launchEndTime = 0
    }
}
