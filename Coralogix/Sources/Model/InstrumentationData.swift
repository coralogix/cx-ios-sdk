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

    // Mirrors the web SDK's buildRumContextAttributes(), using cx_rum.* prefixed keys.
    // N/A mobile fields (browser, browserVersion, url_blueprint, resource_context) are omitted.
    private static func buildRumContextAttributes(cxRum: CxRum, viewManager: ViewManager?) -> [String: Any] {
        var attrs = [String: Any]()

        // Mobile SDK version (browser SDK equivalent: cx_rum.browser_sdk.version)
        attrs["cx_rum.mobile_sdk.version"] = cxRum.mobileSDK.sdkFramework.version

        // Environment & platform
        if !cxRum.environment.isEmpty {
            attrs["cx_rum.environment"] = cxRum.environment
        }
        let platform = (Global.getOs() == Keys.tvos.rawValue) ? Keys.television.rawValue : Keys.mobile.rawValue
        attrs["cx_rum.platform"] = platform

        // Version metadata
        attrs["cx_rum.version_metadata.app_name"] = cxRum.versionMetadata.appName
        attrs["cx_rum.version_metadata.app_version"] = cxRum.versionMetadata.appVersion

        // Labels — all customer labels as a single nested map under cx_rum.labels
        if let labels = cxRum.labels, !labels.isEmpty {
            attrs["cx_rum.labels"] = labels
        }

        // Session context
        if let session = cxRum.sessionContext {
            attrs["cx_rum.session_context.session_id"] = session.sessionId
            if !session.userId.isEmpty    { attrs["cx_rum.session_context.user_id"]    = session.userId }
            if !session.userName.isEmpty  { attrs["cx_rum.session_context.user_name"]  = session.userName }
            if !session.userEmail.isEmpty { attrs["cx_rum.session_context.user_email"] = session.userEmail }
        }
        attrs["cx_rum.session_context.os"]         = Global.getOs()
        attrs["cx_rum.session_context.osVersion"]  = Global.osVersionInfo()
        attrs["cx_rum.session_context.device"]     = Global.getDeviceModel()
        attrs["cx_rum.session_context.user_agent"] = UserAgentManager.shared.getUserAgent()

        // Event context
        attrs["cx_rum.event_context.type"]     = cxRum.eventContext.type.rawValue
        attrs["cx_rum.event_context.severity"] = cxRum.eventContext.severity
        if !cxRum.eventContext.source.isEmpty {
            attrs["cx_rum.event_context.source"] = cxRum.eventContext.source
        }

        // Error context
        if !cxRum.errorContext.errorType.isEmpty {
            attrs["cx_rum.error_context.error_type"] = cxRum.errorContext.errorType
        }
        if !cxRum.errorContext.errorMessage.isEmpty {
            attrs["cx_rum.error_context.error_message"] = cxRum.errorContext.errorMessage
        }

        // Network request context (only for network-request events)
        if cxRum.eventContext.type == .networkRequest {
            let nrc = cxRum.networkRequestContext
            attrs["cx_rum.network_request_context.url"]         = nrc.url
            attrs["cx_rum.network_request_context.method"]      = nrc.method
            attrs["cx_rum.network_request_context.status_code"] = nrc.statusCode
            attrs["cx_rum.network_request_context.status_text"] = nrc.statusText
            attrs["cx_rum.network_request_context.fragments"]   = nrc.fragments
        }

        // Page context — iOS uses the visible view-controller name as the page URL
        if let pageUrl = viewManager?.getDictionary()[Keys.view.rawValue] as? String {
            attrs["cx_rum.page_context.page_url"]       = pageUrl
            attrs["cx_rum.page_context.page_fragments"] = pageUrl
        }

        return attrs
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
        result[Keys.status.rawValue] = self.status
        result[Keys.kind.rawValue] = self.kind
        result[Keys.duration.rawValue] = self.duration
        if let sessionId = self.sessionId { result[Keys.keySessionId.rawValue] = sessionId }
        return result
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
