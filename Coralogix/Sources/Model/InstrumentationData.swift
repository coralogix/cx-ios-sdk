//
//  InstrumentationData.swift
//
//
//  Created by Coralogix Dev Team on 29/07/2024.
//

import Foundation
import CoralogixInternal

struct InstrumentationData {
    let otelSpan: OtelSpan
    let otelResource: OtelResource
 
    init(otel: SpanDataProtocol, cxRum: CxRum, viewManager: ViewManager?) {
        self.otelSpan = OtelSpan(otel: otel, cxRum: cxRum, viewManager: viewManager)
        self.otelResource = OtelResource(otel: otel)
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.otelSpan.rawValue] = self.otelSpan.getDictionary()
        result[Keys.otelResource.rawValue] = self.otelResource.getDictionary()
        return result
    }
}

/// RUM `instrumentation_data.otelSpan` payload (see `getDictionary()`).
///
/// **Ingestion contract:** coordinate changes with the backend/RUM pipeline owners. Mixed SDK versions
/// in the field may require the server to accept more than one shape during rollout.
/// - Top-level span identity and timing use **camelCase** (`traceId`, `spanId`, `startTime`, …).
///   Legacy OTLP **snake_case duplicate mirror keys** that nested the same information again under
///   `otelSpan` were removed on purpose; tracing extractors must not depend on those mirrors.
/// - `status.code` is an OTLP **integer** enum (`0` unset, `1` ok, `2` error), not `STATUS_CODE_*` strings.
/// - `kind` is emitted as an OTLP SpanKind **integer** (i32), not a string name.
struct OtelSpan {
    let spanId: String
    let traceId: String
    let parentSpanId: String?
    let name: String
    let attributes: [String: Any]
    let startTime: [UInt64]
    let endTime: [UInt64]
    let status: [String: Any]
    let kind: Int
    let duration: [UInt64]
    let sessionId: String?
    
    init(otel: SpanDataProtocol, cxRum: CxRum, viewManager: ViewManager?) {
        let traceContext = Helper.getTraceAndSpanId(otel: otel)
        self.traceId = traceContext.traceId
        self.spanId = traceContext.spanId
        self.parentSpanId = otel.getParentSpanId()
        self.sessionId = cxRum.sessionContext?.sessionId
        self.name = otel.getName() ?? ""
        self.attributes = OtelSpan.buildRumContextAttributes(cxRum: cxRum, viewManager: viewManager)

        let currentDate = Date().timeIntervalSince1970
        let defaultTime = [UInt64(currentDate), 0]
        if let startTime = otel.getStartTime() {
            self.startTime = startTime.openTelemetryFormat
        } else {
            self.startTime = defaultTime
        }
        
        if let endTime = otel.getEndTime() {
            self.endTime = endTime.openTelemetryFormat
        } else {
            self.endTime = defaultTime
        }
        
        self.status = otel.getStatusCode()
        self.kind = otel.getKind()
        if let startTime = otel.getStartTime(),
           let endTime = otel.getEndTime() {
            let delta = endTime - startTime
            self.duration = delta.openTelemetryFormat
        } else {
            self.duration = [0, 0]
        }
    }

    // MARK: - cx_rum.* attribute key constants
    // Centralised to prevent silent data loss from typos — a misspelled key would
    // be silently ignored by the backend with no compile-time warning.
    private enum AttrKey {
        static let mobileSdkVersion          = "cx_rum.mobile_sdk.version"
        static let environment               = "cx_rum.environment"
        static let platform                  = "cx_rum.platform"
        static let versionMetadataAppName    = "cx_rum.version_metadata.app_name"
        static let versionMetadataAppVersion = "cx_rum.version_metadata.app_version"
        static let labels                    = "cx_rum.labels"
        static let sessionId                 = "cx_rum.session_context.session_id"
        static let sessionCreationDate       = "cx_rum.session_context.session_creation_date"
        static let hasRecording              = "cx_rum.session_context.hasRecording"
        static let userId                    = "cx_rum.session_context.user_id"
        static let userName                  = "cx_rum.session_context.user_name"
        static let userEmail                 = "cx_rum.session_context.user_email"
        static let os                        = "cx_rum.session_context.os"
        static let osVersion                 = "cx_rum.session_context.osVersion"
        static let device                    = "cx_rum.session_context.device"
        static let userAgent                 = "cx_rum.session_context.user_agent"
        static let eventType                 = "cx_rum.event_context.type"
        static let eventSeverity             = "cx_rum.event_context.severity"
        static let eventSource               = "cx_rum.event_context.source"
        static let errorType                 = "cx_rum.error_context.error_type"
        static let errorMessage              = "cx_rum.error_context.error_message"
        static let networkUrl                = "cx_rum.network_request_context.url"
        static let networkMethod             = "cx_rum.network_request_context.method"
        static let networkStatusCode         = "cx_rum.network_request_context.status_code"
        static let networkStatusText         = "cx_rum.network_request_context.status_text"
        static let networkFragments          = "cx_rum.network_request_context.fragments"
        static let networkRequestHeaders     = "cx_rum.network_request_context.request_headers"
        static let networkResponseHeaders    = "cx_rum.network_request_context.response_headers"
        static let networkRequestPayload     = "cx_rum.network_request_context.request_payload"
        static let networkResponsePayload    = "cx_rum.network_request_context.response_payload"
        static let pageUrl                   = "cx_rum.page_context.page_url"
        static let pageFragments             = "cx_rum.page_context.page_fragments"
    }

    // Mirrors the web SDK's buildRumContextAttributes(), using cx_rum.* prefixed keys.
    // N/A mobile fields (browser, browserVersion, url_blueprint, resource_context) are omitted.
    //
    // CX-44686: dictionary variant — reads the same fields from the post-`beforeSend`
    // cx_rum dictionary (as produced by `CxRumPayloadBuilder.build()` / `mergeDictionaries`)
    // so that customer modifications applied via `beforeSend` propagate into
    // `instrumentation_data.otelSpan.attributes` and not just into `text.cx_rum`.
    // The two destinations of a span must carry the same final attribute values.
    internal static func buildRumContextAttributes(
        fromCxRumDict cxRumDict: [String: Any],
        viewManager: ViewManager?,
        mobileSdkVersion: String
    ) -> [String: Any] {
        var attrs = [String: Any]()

        attrs[AttrKey.mobileSdkVersion] = mobileSdkVersion

        if let env = cxRumDict[Keys.environment.rawValue] as? String, !env.isEmpty {
            attrs[AttrKey.environment] = env
        }
        let platform = (Global.getOs() == Keys.tvos.rawValue) ? Keys.television.rawValue : Keys.mobile.rawValue
        attrs[AttrKey.platform] = platform

        if let vm = cxRumDict[Keys.versionMetaData.rawValue] as? [String: Any] {
            attrs[AttrKey.versionMetadataAppName]    = vm[Keys.appName.rawValue]
            attrs[AttrKey.versionMetadataAppVersion] = vm[Keys.appVersion.rawValue]
        }

        if let labels = cxRumDict[Keys.labels.rawValue] as? [String: Any], !labels.isEmpty {
            attrs[AttrKey.labels] = labels
        }

        if let session = cxRumDict[Keys.sessionContext.rawValue] as? [String: Any] {
            if let v = session[Keys.sessionId.rawValue] as? String { attrs[AttrKey.sessionId] = v }
            if let v = session[Keys.sessionCreationDate.rawValue] { attrs[AttrKey.sessionCreationDate] = v }
            if let v = session[Keys.hasRecording.rawValue] as? Bool { attrs[AttrKey.hasRecording] = v }
            if let v = session[Keys.userId.rawValue] as? String, !v.isEmpty { attrs[AttrKey.userId] = v }
            if let v = session[Keys.userName.rawValue] as? String, !v.isEmpty { attrs[AttrKey.userName] = v }
            if let v = session[Keys.userEmail.rawValue] as? String, !v.isEmpty { attrs[AttrKey.userEmail] = v }
        }
        attrs[AttrKey.os]        = Global.getOs()
        attrs[AttrKey.osVersion] = Global.osVersionInfo()
        attrs[AttrKey.device]    = Global.getDeviceModel()
        attrs[AttrKey.userAgent] = UserAgentManager.shared.getUserAgent()

        if let event = cxRumDict[Keys.eventContext.rawValue] as? [String: Any] {
            if let v = event[Keys.type.rawValue]     { attrs[AttrKey.eventType]     = v }
            if let v = event[Keys.severity.rawValue] { attrs[AttrKey.eventSeverity] = v }
            if let v = event[Keys.source.rawValue] as? String, !v.isEmpty { attrs[AttrKey.eventSource] = v }
        }

        if let err = cxRumDict[Keys.errorContext.rawValue] as? [String: Any] {
            if let v = err[Keys.errorType.rawValue] as? String, !v.isEmpty { attrs[AttrKey.errorType] = v }
            if let v = err[Keys.errorMessage.rawValue] as? String, !v.isEmpty { attrs[AttrKey.errorMessage] = v }
        }

        if let net = cxRumDict[Keys.networkRequestContext.rawValue] as? [String: Any],
           let url = net[Keys.url.rawValue] as? String, !url.isEmpty {
            attrs[AttrKey.networkUrl]        = url
            attrs[AttrKey.networkMethod]     = net[Keys.method.rawValue]
            attrs[AttrKey.networkStatusCode] = net[Keys.statusCode.rawValue]
            attrs[AttrKey.networkStatusText] = net[Keys.statusText.rawValue]
            attrs[AttrKey.networkFragments]  = net[Keys.fragments.rawValue]
            if let h = net[Keys.requestHeaders.rawValue]  { attrs[AttrKey.networkRequestHeaders]  = h }
            if let h = net[Keys.responseHeaders.rawValue] { attrs[AttrKey.networkResponseHeaders] = h }
            if let p = net[Keys.requestPayload.rawValue]  { attrs[AttrKey.networkRequestPayload]  = p }
            if let p = net[Keys.responsePayload.rawValue] { attrs[AttrKey.networkResponsePayload] = p }
        }

        if let pageUrl = viewManager?.getDictionary()[Keys.view.rawValue] as? String, !pageUrl.isEmpty {
            attrs[AttrKey.pageUrl]       = pageUrl
            attrs[AttrKey.pageFragments] = pageUrl
        }

        return attrs
    }

    private static func buildRumContextAttributes(cxRum: CxRum, viewManager: ViewManager?) -> [String: Any] {
        var attrs = [String: Any]()

        // Mobile SDK version (browser SDK equivalent: cx_rum.browser_sdk.version)
        attrs[AttrKey.mobileSdkVersion] = cxRum.mobileSDK.sdkFramework.version

        // Environment & platform
        if !cxRum.environment.isEmpty {
            attrs[AttrKey.environment] = cxRum.environment
        }
        let platform = (Global.getOs() == Keys.tvos.rawValue) ? Keys.television.rawValue : Keys.mobile.rawValue
        attrs[AttrKey.platform] = platform

        // Version metadata
        attrs[AttrKey.versionMetadataAppName]    = cxRum.versionMetadata.appName
        attrs[AttrKey.versionMetadataAppVersion] = cxRum.versionMetadata.appVersion

        // Labels — all customer labels as a single nested map under cx_rum.labels
        if let labels = cxRum.labels, !labels.isEmpty {
            attrs[AttrKey.labels] = labels
        }

        // Session context
        if let session = cxRum.sessionContext {
            attrs[AttrKey.sessionId] = session.sessionId
            attrs[AttrKey.sessionCreationDate] = session.sessionCreationDate.milliseconds
            attrs[AttrKey.hasRecording] = session.hasRecording
            if !session.userId.isEmpty    { attrs[AttrKey.userId]    = session.userId }
            if !session.userName.isEmpty  { attrs[AttrKey.userName]  = session.userName }
            if !session.userEmail.isEmpty { attrs[AttrKey.userEmail] = session.userEmail }
        }
        attrs[AttrKey.os]        = Global.getOs()
        attrs[AttrKey.osVersion] = Global.osVersionInfo()
        attrs[AttrKey.device]    = Global.getDeviceModel()
        attrs[AttrKey.userAgent] = UserAgentManager.shared.getUserAgent()

        // Event context
        attrs[AttrKey.eventType]     = cxRum.eventContext.type.rawValue
        attrs[AttrKey.eventSeverity] = cxRum.eventContext.severity
        if !cxRum.eventContext.source.isEmpty {
            attrs[AttrKey.eventSource] = cxRum.eventContext.source
        }

        // Error context
        if !cxRum.errorContext.errorType.isEmpty {
            attrs[AttrKey.errorType] = cxRum.errorContext.errorType
        }
        if !cxRum.errorContext.errorMessage.isEmpty {
            attrs[AttrKey.errorMessage] = cxRum.errorContext.errorMessage
        }

        // Network request context (only for network-request events with a valid URL)
        if cxRum.eventContext.type == .networkRequest {
            let nrc = cxRum.networkRequestContext
            if !nrc.url.isEmpty {
                attrs[AttrKey.networkUrl]        = nrc.url
                attrs[AttrKey.networkMethod]     = nrc.method
                attrs[AttrKey.networkStatusCode] = nrc.statusCode
                attrs[AttrKey.networkStatusText] = nrc.statusText
                attrs[AttrKey.networkFragments]  = nrc.fragments
                if let v = nrc.requestHeaders  { attrs[AttrKey.networkRequestHeaders]  = v }
                if let v = nrc.responseHeaders { attrs[AttrKey.networkResponseHeaders] = v }
                if let v = nrc.requestPayload  { attrs[AttrKey.networkRequestPayload]  = v }
                if let v = nrc.responsePayload { attrs[AttrKey.networkResponsePayload] = v }
            }
        }

        // Page context — iOS uses the visible view-controller name as the page URL.
        // Guard against empty string returned when no view is active.
        if let pageUrl = viewManager?.getDictionary()[Keys.view.rawValue] as? String,
           !pageUrl.isEmpty {
            attrs[AttrKey.pageUrl]       = pageUrl
            attrs[AttrKey.pageFragments] = pageUrl
        }

        return attrs
    }

    /// Maps span status to OTLP status code integer (proto enum: UNSET=0, OK=1, ERROR=2).
    /// Production `SpanData.getStatusCode()` always supplies `code` as `Int`; string branches are for
    /// numeric strings and legacy OTLP status names from tests or external `SpanDataProtocol` stubs.
    private static func otlpStatusCode(from statusDict: [String: Any]) -> [String: Any] {
        let raw = statusDict[Keys.code.rawValue]
        let code: Int = {
            if let i = raw as? Int { return i }
            guard let s = raw as? String else { return 0 }
            switch s {
            case "STATUS_CODE_OK": return 1
            case "STATUS_CODE_ERROR": return 2
            default: break
            }
            return Int(s) ?? 0
        }()
        let otlpCode: Int
        switch code {
        case 1: otlpCode = 1  // STATUS_CODE_OK
        case 2: otlpCode = 2  // STATUS_CODE_ERROR
        default: otlpCode = 0 // STATUS_CODE_UNSET
        }
        return [Keys.code.rawValue: otlpCode]
    }

    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.spanId.rawValue] = self.spanId
        result[Keys.traceId.rawValue] = self.traceId
        if let parentSpanId = self.parentSpanId { result[Keys.parentSpanId.rawValue] = parentSpanId }
        result[Keys.name.rawValue] = self.name
        result[Keys.attributes.rawValue] = self.attributes
        result[Keys.startTime.rawValue] = self.startTime
        result[Keys.endTime.rawValue] = self.endTime
        result[Keys.status.rawValue] = Self.otlpStatusCode(from: self.status)
        result[Keys.kind.rawValue] = Self.otlpSpanKind(from: self.kind)
        result[Keys.duration.rawValue] = self.duration
        if let sessionId = self.sessionId { result[Keys.keySessionId.rawValue] = sessionId }
        return result
    }

    /// Maps OTel SDK SpanKind to OTLP proto SpanKind integer (backend expects i32).
    /// OTel SDK: 0=INTERNAL,1=SERVER,2=CLIENT,3=PRODUCER,4=CONSUMER
    /// OTLP proto: 0=UNSPECIFIED,1=INTERNAL,2=SERVER,3=CLIENT,4=PRODUCER,5=CONSUMER
    private static func otlpSpanKind(from kind: Int) -> Int {
        switch kind {
        case 0: return 1  // INTERNAL
        case 1: return 2  // SERVER
        case 2: return 3  // CLIENT
        case 3: return 4  // PRODUCER
        case 4: return 5  // CONSUMER
        default: return 0 // UNSPECIFIED
        }
    }
}

struct OtelResource {
    let attributes: [String: Any]
    
    init(otel: SpanDataProtocol) {
        self.attributes = otel.getResources()
    }
    
    func getDictionary() -> [String: Any] {
        return [Keys.attributes.rawValue: self.attributes]
    }
}
