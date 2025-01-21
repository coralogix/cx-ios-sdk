//
//  Enums.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum CoralogixLogSeverity: Int {
    case debug = 1
    case verbose = 2
    case info = 3
    case warn = 4
    case error = 5
    case critical = 6
}

enum CoralogixEventType: String {
    case error
    case networkRequest = "network-request"
    case log
    case userInteraction = "user-interaction"
    case webVitals = "web-vitals"
    case longtask
    case resources
    case internalKey = "internal"
    case navigation
    case mobileVitals = "mobile-vitals"
    case lifeCycle = "life-cycle"
    case unknown
}
