//
//  WarmDetector.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 15/09/2025.
//

import Foundation
import UIKit

final class WarmDetector {
    var foregroundStartTime: CFAbsoluteTime?
    var foregroundEndTime: CFAbsoluteTime?
    var warmMetricIsActive = false
    var warmStartDurationsMs: Double?

    func startMonitoring() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.appDidEnterBackgroundNotification),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        
        let sdk = CoralogixRum.mobileSDK.sdkFramework

        switch sdk {
        case .flutter, .reactNative:
            // it's flutter or react-native
            break
        case .swift:
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.appWillEnterForegroundNotification),
                                                   name: UIApplication.willEnterForegroundNotification,
                                                   object: nil)
            
            NotificationCenter.default.addObserver(self, selector: #selector(self.appDidBecomeActiveNotification),
                                                   name: UIApplication.didBecomeActiveNotification,
                                                   object: nil)
        }
    }
    
    @objc internal func appWillEnterForegroundNotification() {
        if warmMetricIsActive {
            self.foregroundStartTime = CFAbsoluteTimeGetCurrent()
            self.foregroundEndTime = nil
            self.warmMetricIsActive = false
        }
    }
    
    @objc func appDidEnterBackgroundNotification() {
        self.warmMetricIsActive = true
    }
    
    @objc internal func appDidBecomeActiveNotification() {
        if let foregroundStartTime = self.foregroundStartTime,
           self.foregroundEndTime == nil {
            let currentTime = CFAbsoluteTimeGetCurrent()
            self.foregroundEndTime = currentTime
            let warmStartDuration = (currentTime - foregroundStartTime) * 1000
    
            warmStartDurationsMs = (warmStartDuration)

//            Log.d("[Metric] Warm start duration: \(warmStartRounded) milliseconds")
        }
    }
    
    func statsDictionary() -> [String: Any] {
        guard let value = warmStartDurationsMs else { return [:] }
        return [
            MobileVitalsType.warm.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.milliseconds.stringValue,
                Keys.value.rawValue: value
            ]
        ]
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
