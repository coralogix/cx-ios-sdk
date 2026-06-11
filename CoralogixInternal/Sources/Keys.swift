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
    case nativeVersion = "native_version"
    case sessionId = "session_id"
    case sessionCreationDate = "session_creation_date"
    case prevSessionCreationDate
    case prevSessionId
    case prevPid
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
    case targetElementInnerText = "target_element_inner_text"
    case scrollDirection = "scroll_direction"
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
    case requestHeaders = "request_headers"
    case responseHeaders = "response_headers"
    case requestPayload = "request_payload"
    case responsePayload = "response_payload"
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
    // CX-44687: keychain slot for the per-process boot UUID written alongside
    // `pid` in SessionMetadata.loadPrevSession. Used by ViewManager.init as a
    // PID-recycling defense — see Global.processBootUUID.
    case bootUUID
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
    // CX-44687: product-analytics fields at the cx_rum top level.
    // Per-field naming chosen to match Browser's wire shape (Daniel, 2026-06-08):
    //   - view_number  → snake_case
    //   - isNavigationEvent → camelCase
    case viewNumber = "view_number"
    case isNavigationEvent
    // Keychain slot (NOT a wire key). The rawValue "viewNumber" is the SecItem
    // account name we read/write — distinct from `Keys.viewNumber` above whose
    // rawValue is "view_number". Confusing them at a callsite would silently
    // store the counter under the wrong slot and break the restore path.
    case storedViewNumber = "viewNumber"
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
    case internalContext = "internal_context"
    case elementId = "element_id"
    case eventName = "event_name"
    case elementType = "element_type"
    case click
    case errorMessage = "error_message"
    case isCrash = "is_crash"
    case buildId = "build_id"
    case stackTraceType = "stack_trace_type"
    case virt = "virt"
    case obfuscated = "obfuscated"
    case tvos
    case television
    case mobileVitalsContext = "mobile_vitals_context"
    case lifeCycleContext = "life_cycle_context"
    case mobileVitalsType
    case mobileVitalsValue
    case mobileVitalsUnits = "units"
    case value
    case anrString = "application_not_responding"
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
    case containsSwiftUIContent
    case screenshotContext = "screenshot_context"
    case queueScreenshotManager = "com.coralogix.screenshotmanager.queue"
    case queueExporter = "com.coralogix.exporter.queue"
    case queueSdkManager = "com.coralogix.sdkmanager.queue"
    case queueFileOperations = "com.coralogix.fileoperations"
    case queueUrlProcessing = "com.coralogix.urlProcessing"
    case queueMediaInput = "com.coralogix.mediainput"
    case queueSpanProcessingQueue = "com.coralogix.spanProcessingQueue"
    case queueViewManagerQueue = "com.coralogix.viewManagerQueue"
    case queueSlowFrozenReporterQueue = "com.coralogix.vitals.slowfrozen.reporter"
    case queueUserAgentQueue = "com.coralogix.userAgentQueue"
    case undefined = ""
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
    case fps
    case cold
    case warm
    case anr
    case cpuUsage = "cpu_usage"
    case totalCpuTime = "total_cpu_time"
    case mainThreadCpuTime = "main_thread_cpu_time"
    case residentMemory = "resident_memory"
    case memoryUtilization = "memory_utilization"
    case slowFrames = "slow_frames"
    case frozenFrames = "frozen_frames"
    case footprintMemory = "footprint_memory"
    case metricKit = "metric_kit"
    case ms
    case kb
    case mb
    case count
    case percentage
    case cpu
    case memory
    case fingerPrint
    case event
    case initKey = "init"
    case version
    case instrumentations
    case ignoreUrls
    case ignoreErrors
    case collectIPData
    case sessionSampleRate
    case excludeFromSampling
    case traceParentInHeader
    case debug
    case proxyUrl
    case enableSwizzling
    case beforeSend
    case exists
    case min
    case max
    case avg
    case p95
    case slowFrozen = "slow_frozen"
    case customMeasurementContext = "custom_measurement_context"
    case mobileVitals
}

/// Wire-format constant **values** (not keys) emitted on spans. Kept
/// separate from `Keys` so the "keys" enum stays purely a registry of
/// attribute names — see the CLAUDE.md rule that all attribute keys live
/// in `Keys.swift`. Values that flow into attribute slots live here.
public enum WireValues: String {
    /// `error_message` value emitted for ANR-derived error events.
    case anrErrorMessage = "Application Not Responding"
    /// `error_type` discriminator emitted for ANR-derived error events.
    case anrErrorType = "ANR"
}

public enum CoralogixLogSeverity: Int {
    case debug = 1
    case verbose = 2
    case info = 3
    case warn = 4
    case error = 5
    case critical = 6
}

public enum CoralogixEventType: String, Codable {
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
    case customMeasurement = "custom-measurement"
    /// Manual spans from `getCustomTracer()` (parity with Browser SDK `CoralogixEventType.CUSTOM_SPAN`).
    case customSpan = "custom-span"
    case unknown
}

/// Public-facing instrumentation categories that can be excluded from session sampling.
///
/// Pass via `CoralogixExporterOptions.excludeFromSampling` to keep emitting these event
/// types regardless of the session sample-rate decision. Mirrors the browser SDK's
/// `ExcludableInstrumentation` (PR #800, v3.8.0).
public enum ExcludableInstrumentation: String, CaseIterable, Sendable {
    case errors
    case logs
    case network
    case userInteractions
    case mobileVitals
    case customSpan
    case customMeasurement

    /// Internal `CoralogixEventType` this public case maps to.
    public var eventType: CoralogixEventType {
        switch self {
        case .errors: return .error
        case .logs: return .log
        case .network: return .networkRequest
        case .userInteractions: return .userInteraction
        case .mobileVitals: return .mobileVitals
        case .customSpan: return .customSpan
        case .customMeasurement: return .customMeasurement
        }
    }
}
