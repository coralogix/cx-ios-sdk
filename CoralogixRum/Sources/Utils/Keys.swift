//
//  Keys.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import UIKit

public enum Keys: String {
    case appName = "app_name"
    case appVersion = "app_version"
    case networkConnectionType = "network_connection_type"
    case networkConnectionSubtype = "network_connection_subtype"
    case cxRum = "cx_rum"
    case labels
    case text
    case iosSdk = "ios_sdk"
    case errorContext = "error_context"
    case sdkVersion = "sdk_version"
    case sessionId = "session_id"
    case sessionCreationDate = "session_creation_date"
    case userAgent = "user_agent"
    case browser
    case browserVersion
    case operatingSystem = "os"
    case osVersion
    case device
    case userId = "user_id"
    case userName = "user_name"
    case userEmail = "user_email"
    case userMetadata = "user_metadata"
    case timestamp
    case environment
    case versionMetaData = "version_metadata"
    case sessionContext = "session_context"
    case prevSession = "prev_session"
    case eventContext = "event_context"
    case type
    case source
    case severity
    case applicationName
    case subsystemName
    case logs
    case locationHref = "location_href"
    case eventType = "event_type"
    case applicationContext = "application_context"
    case userContext = "user_context"
    case deviceState = "device_state"
    case viewContext = "view_context"
    case viewController
    case country
    case cxLog = "cx_log"
    case customLabels = "custom_labels"
    case interactionEventName = "interaction_event_name"
    case elementInnerText = "element_inner_text"
    case elementInnerHtml = "element_inner_html"
    case elementClasses =  "element_classes"
    case targetXpath = "target_xpath"
    case targetElement = "target_element"
    case targetElementType = "target_element_type"
    case fetch
    case networkRequestContext = "network_request_context"
    case method
    case duration
    case schema
    case statusCode = "status_code"
    case statusText = "status_text"
    case url
    case host
    case responseContentLength = "response_content_length"
    case fragments
    case traceId
    case spanId
    case callStackSymbols = "call_stack_symbols"
    case console
    case code
    case domain
    case localizedDescription = "localized_description"
    case userInfo = "user_info"
    case originalStackTrace = "original_stacktrace"
    case exceptionType = "exception_type"
    case arch
    case crashTimestamp = "crash_timestamp"
    case processName = "process_name"
    case baseAddress = "base_address"
    case applicationIdentifier = "application_identifier"
    case triggeredByThread = "triggered_by_thread"
    case message
    case data
    case logContext = "log_context"
    case pid
    case frameNumber = "frame_number"
    case binary
    case functionAdresseCalled = "function_adresse_called"
    case base
    case offset
    case exceptionContext = "exception_context"
    case crashContext = "crash_context"
    case platform
    case mobile
    case mobileSdk = "mobile_sdk"
    case framework
    case swift
    case ios
}

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
    case unknown
}

public enum Global: String {
    case iosSdk = "1.0.0"
    case coralogixPath = "/browser/v1beta/logs"
    
    enum BatchSpan: Int {
        case maxExportBatchSize = 50
        case scheduleDelay = 2
    }
    
    public static func appVersionInfo(indludeBuild: Bool = true) -> String {
        let dictionary = Bundle.main.infoDictionary!
        if let version = dictionary["CFBundleShortVersionString"] as? String,
           let build = dictionary["CFBundleVersion"] as? String {
            return indludeBuild ? version + " (" + build + ")" : version
        }
        return ""
    }
    
    public static func getOs() -> String {
        return UIDevice.current.systemName
    }
    
    public static func appName() -> String {
        return ProcessInfo.processInfo.processName
    }
    
    public static func osVersionInfo() -> String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }
    
    public static func getDeviceModel() -> String {
        return UIDevice.current.model
    }
}

public enum CoralogixDomain: String {
    case EU1 = "https://ingress.eu1.rum-ingress-coralogix.com" // eu-west-1 (Ireland)
    case EU2 = "https://ingress.eu2.rum-ingress-coralogix.com" // eu-north-1 (Stockholm)
    case US1 = "https://ingress.us1.rum-ingress-coralogix.com" // us-east-2 (Ohio)
    case US2 = "https://ingress.us2.rum-ingress-coralogix.com" // us-west-2 (Oregon)
    case AP1 = "https://ingress.ap1.rum-ingress-coralogix.com" // ap-south-1 (Mumbai)
    case AP2 = "https://ingress.ap2.rum-ingress-coralogix.com" // ap-southeast-1 (Singapore)
    
    func stringValue() -> String {
        switch self {
        case .EU1:
            return "EU1"
        case .EU2:
            return "EU2"
        case .US1:
            return "US1"
        case .US2:
            return "US2"
        case .AP1:
            return "AP1"
        case .AP2:
            return "AP2"
        }
    }
}
