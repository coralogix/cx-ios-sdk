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
    case actionCount
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
    case application
    case segmentIndex
    case segmentSize
    case segmentTimestamp
    case keySessionCreationDate = "sessionCreationDate"
    case subIndex
    case metaData
    case events
    case chunk
    case hasRecording
    case snapshotId
    case snapshotCreationTime
    case screenshotId
    case page
    case screenshotData
    case screenshotContext = "screenshot_context"
    case queueScreenshotManager = "com.coralogix.screenshotmanager.queue"
    case queueExporter = "com.coralogix.exporter.queue"
    case queueSdkManager = "com.coralogix.sdkmanager.queue"
    case queueFileOperations = "com.coralogix.fileoperations"
    case queueUrlProcessing = "com.coralogix.urlProcessing"
    case queueMediaInput = "com.coralogix.mediainput"
    case queueSpanProcessingQueue = "com.coralogix.spanProcessingQueue"
    case undefined = "N/A"
    case cxforward
    case enable
    case options
    case allowedTracingUrls
    case customTraceId
    case customSpanId
    case isManual
    case metricKitLog = "metricKit log"
    case idle
    case active
}

public enum CoralogixLogSeverity: Int {
    case debug = 1
    case verbose = 2
    case info = 3
    case warn = 4
    case error = 5
    case critical = 6
}

public enum CoralogixEventType: String {
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
    case screenshot
    case unknown
}
