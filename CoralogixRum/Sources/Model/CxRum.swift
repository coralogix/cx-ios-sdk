//
//  CxRum.swift
//  Elastiflix-iOS
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import OpenTelemetrySdk

struct CxRum {
    let timeStamp: TimeInterval
    let eventTypeContext: EventTypeContext
    let mobileSdk: String
    let versionMetadata: VersionMetadata
    var sessionContext: SessionContext?
    var prevSessionContext: SessionContext?
    var sessionManager: SessionManager?
    let eventContext: EventContext
    let logContext: LogContext
    let environment: String
    let traceId: String
    let spanId: String
    let errorContext: ErrorContext
    let deviceContext: DeviceContext
    let viewContext: String? = nil
    var labels: [String: Any]?
    
    init(otelSpan: SpanData,
         versionMetadata: VersionMetadata,
         sessionManager: SessionManager,
         userMetadata: [String: String]?,
         labels: [String: Any]?) {
        self.timeStamp = otelSpan.startTime.timeIntervalSince1970
        self.eventTypeContext = EventTypeContext(otel: otelSpan)
        self.mobileSdk = Global.iosSdk.rawValue
        self.versionMetadata = versionMetadata
        self.sessionManager = sessionManager
        
        if let sessionMetadata = sessionManager.getSessionMetadata() {
            self.sessionContext = SessionContext(otel: otelSpan,
                                                 versionMetadata: versionMetadata,
                                                 sessionMetadata: sessionMetadata,
                                                 userMetadata: userMetadata)
            if let prevSessionMetadata = sessionManager.getPrevSessionMetadata() {
                self.prevSessionContext = SessionContext(otel: otelSpan,
                                                         versionMetadata: versionMetadata,
                                                         sessionMetadata: prevSessionMetadata,
                                                         userMetadata: userMetadata)
            }
        }
        self.eventContext = EventContext(otel: otelSpan)
        self.environment = otelSpan.attributes[Keys.environment.rawValue]?.description ?? ""
        self.traceId = otelSpan.traceId.hexString
        self.spanId = otelSpan.spanId.hexString
        self.errorContext = ErrorContext(otel: otelSpan)
        self.deviceContext = DeviceContext(otel: otelSpan)
        self.labels = labels
        self.logContext = LogContext(otel: otelSpan)
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.timestamp.rawValue] = self.timeStamp.milliseconds
        result[Keys.mobileSdk.rawValue] = [Keys.sdkVersion.rawValue: self.mobileSdk,
                                           Keys.framework.rawValue: Keys.swift.rawValue,
                                           Keys.operatingSystem.rawValue: Keys.ios.rawValue]
        result[Keys.versionMetaData.rawValue] =  self.versionMetadata.getDictionary()
        result[Keys.sessionContext.rawValue] = self.sessionContext?.getDictionary()
        result[Keys.eventContext.rawValue] = self.eventContext.getDictionary()
        result[Keys.environment.rawValue] = self.environment
        result[Keys.traceId.rawValue] = self.traceId
        result[Keys.spanId.rawValue] = self.spanId
        result[Keys.platform.rawValue] = Keys.mobile.rawValue
        result[Keys.deviceState.rawValue] = self.deviceContext.getDictionary()
        
        if let prevSessionContext = self.prevSessionContext {
            result[Keys.prevSession.rawValue] = prevSessionContext.getPrevSessionDictionary()
        }
        
        if eventContext.type == CoralogixEventType.error {
            result[Keys.errorContext.rawValue] = self.errorContext.getDictionary()
        }
        
        if eventContext.type == CoralogixEventType.networkRequest {
            result[Keys.networkRequestContext.rawValue] = self.eventTypeContext.getDictionary()
        }
        
        if eventContext.type == CoralogixEventType.log {
            result[Keys.logContext.rawValue] = self.logContext.getDictionary()
        }
        
        if let labels = self.labels {
            result[Keys.labels.rawValue] = labels
        }
        result[Keys.viewContext.rawValue] = [Keys.viewController.rawValue: "Maor_222222"]
        return result
    }
}
