//
//  Keys.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
    case deviceContext = "device_context"
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
    case functionAddressCalled = "function_address_called"
    case base
    case offset
    case platform
    case mobile
    case mobileSdk = "mobile_sdk"
    case framework
    case swift
    case ios
    case emulator
    case deviceName = "device_name"
    case battery
    case networkType = "network_type"
    case view
    case service = "com.coralogix.sdk"
    case keySessionId = "sessionId"
    case keySessionTimeInterval = "sessionTimeInterval"
    case snapshotContext = "snapshot_context"
    case errorCount
    case viewCount
    case clickCount
    case isViewUnique
    case isSnapshotEvent
    case threads
    case httpResponseBodySize = "http_response_body_size"
    case stackTrace
    case instrumentationData = "instrumentation_data"
    case otelResource
    case otelSpan
    case parentSpanId
    case name
    case attributes
    case startTime
    case endTime
    case status
    case kind
    case tapName
    case tapCount
    case tapAttributes
    case tapObject
    case interactionContext = "interaction_context"
    case elementId = "element_id"
    case eventName = "event_name"
    case elementType = "element_type"
    case click
    case errorMessage = "error_message"
    case isCrash = "is_crash"
    case tvos
    case television
    case coldEnd
    case mobileVitalsContext = "mobile_vitals_context"
    case lifeCycleContext = "life_cycle_context"
    case fps = "fps"
    case mobileVitalsType
    case mobileVitalsValue
    case value
    case anr = "application_not_responding"
    case skipEnrichmentWithIp = "skip_enrichment_with_ip"
    case appDidFinishLaunching
    case appDidBecomeActiveNotification
    case appDidEnterBackgroundNotification
    case appWillTerminateNotification
    case applicationDidReceiveMemoryWarning
    case appDidReceiveMemoryWarningNotification
    case positionX = "x"
    case positionY = "y"
    case errorType = "error_type"
    case keyStackTrace = "stack_trace"
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
    case navigation
    case mobileVitals = "mobile-vitals"
    case lifeCycle = "life-cycle"
    case unknown
}

public enum Global: String {
    case sdk = "1.0.17"
    case swiftVersion = "5.9"
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
        return UIDevice.current.systemName.lowercased()
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
    
    public static func modelIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo) // Loads the underlying hardware info into sysinfo
        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
        let identifier = String(bytes: data, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "unknown"
        return identifier
    }
    
    public static var identifier: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        
        let identifier = mirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }()
    
    public static func isEmulator() -> Bool {
#if targetEnvironment(simulator)
        // Code to execute on the Simulator
        return true
#else
        // Code to execute on a real device
        return false
#endif
    }
    // swiftlint:disable function_body_length
    // swiftlint:disable cyclomatic_complexity
    public static func getDeviceName() -> String {
        switch identifier {
#if os(iOS)
        case "iPod5,1": return "iPodTouch5"
        case "iPod7,1": return "iPodTouch6"
        case "iPod9,1": return "iPodTouch7"
        case "iPhone3,1", "iPhone3,2", "iPhone3,3": return "iPhone4"
        case "iPhone4,1": return "iPhone4s"
        case "iPhone5,1", "iPhone5,2": return "iPhone5"
        case "iPhone5,3", "iPhone5,4": return "iPhone5c"
        case "iPhone6,1", "iPhone6,2": return "iPhone5s"
        case "iPhone7,2": return "iPhone6"
        case "iPhone7,1": return "iPhone6Plus"
        case "iPhone8,1": return "iPhone6s"
        case "iPhone8,2": return "iPhone6sPlus"
        case "iPhone9,1", "iPhone9,3": return "iPhone7"
        case "iPhone9,2", "iPhone9,4": return "iPhone7Plus"
        case "iPhone8,4": return "iPhoneSE"
        case "iPhone10,1", "iPhone10,4": return "iPhone8"
        case "iPhone10,2", "iPhone10,5": return "iPhone8Plus"
        case "iPhone10,3", "iPhone10,6": return "iPhoneX"
        case "iPhone11,2": return "iPhoneXS"
        case "iPhone11,4", "iPhone11,6": return "iPhoneXSMax"
        case "iPhone11,8": return "iPhoneXR"
        case "iPhone12,1": return "iPhone11"
        case "iPhone12,3": return "iPhone11Pro"
        case "iPhone12,5": return "iPhone11ProMax"
        case "iPhone12,8": return "iPhoneSE2"
        case "iPhone13,2": return "iPhone12"
        case "iPhone13,1": return "iPhone12Mini"
        case "iPhone13,3": return "iPhone12Pro"
        case "iPhone13,4": return "iPhone12ProMax"
        case "iPhone14,5": return "iPhone13"
        case "iPhone14,4": return "iPhone13Mini"
        case "iPhone14,2": return "iPhone13Pro"
        case "iPhone14,3": return "iPhone13ProMax"
        case "iPhone14,6": return "iPhoneSE3"
        case "iPhone14,7": return "iPhone14"
        case "iPhone14,8": return "iPhone14Plus"
        case "iPhone15,2": return "iPhone14Pro"
        case "iPhone15,3": return "iPhone14ProMax"
        case "iPhone15,4": return "iPhone15"
        case "iPhone15,5": return "iPhone15Plus"
        case "iPhone16,1": return "iPhone15Pro"
        case "iPhone16,2": return "iPhone15ProMax"
        case "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4": return "iPad2"
        case "iPad3,1", "iPad3,2", "iPad3,3": return "iPad3"
        case "iPad3,4", "iPad3,5", "iPad3,6": return "iPad4"
        case "iPad4,1", "iPad4,2", "iPad4,3": return "iPadAir"
        case "iPad5,3", "iPad5,4": return "iPadAir2"
        case "iPad6,11", "iPad6,12": return "iPad5"
        case "iPad7,5", "iPad7,6": return "iPad6"
        case "iPad11,3", "iPad11,4": return "iPadAir3"
        case "iPad7,11", "iPad7,12": return "iPad7"
        case "iPad11,6", "iPad11,7": return "iPad8"
        case "iPad12,1", "iPad12,2": return "iPad9"
        case "iPad13,18", "iPad13,19": return "iPad10"
        case "iPad13,1", "iPad13,2": return "iPadAir4"
        case "iPad13,16", "iPad13,17": return "iPadAir5"
        case "iPad2,5", "iPad2,6", "iPad2,7": return "iPadMini"
        case "iPad4,4", "iPad4,5", "iPad4,6": return "iPadMini2"
        case "iPad4,7", "iPad4,8", "iPad4,9": return "iPadMini3"
        case "iPad5,1", "iPad5,2": return "iPadMini4"
        case "iPad11,1", "iPad11,2": return "iPadMini5"
        case "iPad14,1", "iPad14,2": return "iPadMini6"
        case "iPad6,3", "iPad6,4": return "iPadPro9Inch"
        case "iPad6,7", "iPad6,8": return "iPadPro12Inch"
        case "iPad7,1", "iPad7,2": return "iPadPro12Inch2"
        case "iPad7,3", "iPad7,4": return "iPadPro10Inch"
        case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4": return "iPadPro11Inch"
        case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8": return "iPadPro12Inch3"
        case "iPad8,9", "iPad8,10": return "iPadPro11Inch2"
        case "iPad8,11", "iPad8,12": return "iPadPro12Inch4"
        case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": return "iPadPro11Inch3"
        case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11": return "iPadPro12Inch5"
        case "iPad14,3", "iPad14,4": return "iPadPro11Inch4"
        case "iPad14,5", "iPad14,6": return "iPadPro12Inch6"
        case "AudioAccessory1,1": return "homePod"
        case "i386", "x86_64", "arm64": return ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS"
#endif
        default: return identifier
        // swiftlint:enable function_body_length
        // swiftlint:enable cyclomatic_complexity
        }
    }
}

public enum CoralogixDomain: String {
    case EU1 = "https://ingress.eu1.rum-ingress-coralogix.com" // eu-west-1 (Ireland)
    case EU2 = "https://ingress.eu2.rum-ingress-coralogix.com" // eu-north-1 (Stockholm)
    case US1 = "https://ingress.us1.rum-ingress-coralogix.com" // us-east-2 (Ohio)
    case US2 = "https://ingress.us2.rum-ingress-coralogix.com" // us-west-2 (Oregon)
    case AP1 = "https://ingress.ap1.rum-ingress-coralogix.com" // ap-south-1 (Mumbai)
    case AP2 = "https://ingress.ap2.rum-ingress-coralogix.com" // ap-southeast-1 (Singapore)
    case AP3 = "https://ingress.ap3.rum-ingress-coralogix.com" // ap-southeast-3 (Jakarta)
    case STG = "https://ingress.staging.rum-ingress-coralogix.com"
    
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
        case .AP3:
            return "AP3"
        case .STG:
            return "STG"
        }
    }
}
