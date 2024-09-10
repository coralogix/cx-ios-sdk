//
//  CxRum.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation

struct CxRum {
    var timeStamp: TimeInterval
    let eventTypeContext: EventTypeContext
    let mobileSdk: String
    let versionMetadata: VersionMetadata
    var sessionContext: SessionContext?
    var prevSessionContext: SessionContext?
    var networkManager: NetworkProtocol?
    var sessionManager: SessionManager?
    let eventContext: EventContext
    let logContext: LogContext
    let environment: String
    var traceId: String = ""
    var spanId: String = ""
    let errorContext: ErrorContext
    let deviceContext: DeviceContext
    let deviceState: DeviceState
    let viewContext: String? = nil
    var labels: [String: Any]?
    var viewManager: ViewManager?
    var snapshotContext: SnapshotConext?
    var isOneMinuteFromLastSnapshotPass = false
    var interactionContext: InteractionContext?
    var mobileVitalsContext: MobileVitalsContext?
     
    init(otel: SpanDataProtocol,
         versionMetadata: VersionMetadata,
         sessionManager: SessionManager,
         viewManager: ViewManager,
         networkManager: NetworkProtocol,
         performanceMetricsManager: PerformanceMetricsManager,
         userMetadata: [String: String]?,
         labels: [String: Any]?) {

        self.timeStamp = otel.getStartTime() ?? Date().timeIntervalSince1970
        self.eventTypeContext = EventTypeContext(otel: otel)
        self.mobileSdk = Global.sdk.rawValue
        self.versionMetadata = versionMetadata
        self.sessionManager = sessionManager
        self.networkManager = networkManager
        self.viewManager = viewManager
        
        if let sessionMetadata = sessionManager.getSessionMetadata() {
            self.sessionContext = SessionContext(otel: otel,
                                                 versionMetadata: versionMetadata,
                                                 sessionMetadata: sessionMetadata,
                                                 userMetadata: userMetadata)
            if let prevSessionMetadata = sessionManager.getPrevSessionMetadata() {
                self.prevSessionContext = SessionContext(otel: otel,
                                                         versionMetadata: versionMetadata,
                                                         sessionMetadata: prevSessionMetadata,
                                                         userMetadata: userMetadata)
            }
        }
        self.eventContext = EventContext(otel: otel)
        self.environment = otel.getAttribute(forKey: Keys.environment.rawValue) as? String ?? ""
        self.traceId = otel.getTraceId() ?? ""
        self.spanId = otel.getSpanId() ?? ""
        self.errorContext = ErrorContext(otel: otel)
        self.deviceContext = DeviceContext(otel: otel)
        self.labels = labels
        self.logContext = LogContext(otel: otel)
        self.deviceState = DeviceState(networkManager: self.networkManager)
        self.snapshotContext = SnapshotConext.getSnapshot(otel: otel)
        self.interactionContext = InteractionContext(otel: otel)
        self.mobileVitalsContext = MobileVitalsContext(otel: otel, performanceMetricsManager: performanceMetricsManager)
        
        if let sessionManager = self.sessionManager,
           let viewManager = self.viewManager,
           let lastSnapshotSent = sessionManager.lastSnapshotEventTime {
            if isMoreThanOneMinuteDifference(interval1: lastSnapshotSent.timeIntervalSince1970, interval2: self.timeStamp) {
                self.snapshotContext = SnapshotConext(timestemp: Date().timeIntervalSince1970,
                                                      errorCount: sessionManager.getErrorCount(),
                                                      viewCount: viewManager.getUniqueViewCount(),
                                                      clickCount: sessionManager.getClickCount())
                self.isOneMinuteFromLastSnapshotPass = true
            }
        }
    }
    
    func isMoreThanOneMinuteDifference(interval1: TimeInterval, interval2: TimeInterval) -> Bool {
        let difference = abs(interval1 - interval2)
        return difference > 60
    }

    mutating func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        self.addBasicDetails(to: &result)
        self.addOptionalContexts(to: &result)
        self.addConditionalContexts(to: &result)
        self.addViewManagerContext(to: &result)
        self.addLabels(to: &result)
        self.addMobileVitals(to: &result)
        return result
    }
    
    private func addMobileVitals(to result: inout [String: Any]){
        result[Keys.mobileVitalsContext.rawValue] = self.mobileVitalsContext?.getMobileVitalsDictionary()
    }
    
    private func addBasicDetails(to result: inout [String: Any]) {
        result[Keys.timestamp.rawValue] = self.timeStamp.milliseconds
        result[Keys.mobileSdk.rawValue] = [Keys.sdkVersion.rawValue: self.mobileSdk,
                                           Keys.framework.rawValue: CoralogixRum.sdkFramework.rawValue,
                                           Keys.operatingSystem.rawValue: Global.getOs()]
        result[Keys.versionMetaData.rawValue] = self.versionMetadata.getDictionary()
        result[Keys.sessionContext.rawValue] = self.sessionContext?.getDictionary()
        result[Keys.eventContext.rawValue] = self.eventContext.getDictionary()
        result[Keys.environment.rawValue] = self.environment
        result[Keys.traceId.rawValue] = self.traceId
        result[Keys.spanId.rawValue] = self.spanId
        result[Keys.platform.rawValue] = Global.getOs() == Keys.tvos.rawValue ? Keys.television.rawValue : Keys.mobile.rawValue
        result[Keys.deviceContext.rawValue] = self.deviceContext.getDictionary()
        result[Keys.deviceState.rawValue] = self.deviceState.getDictionary()
    }
    
    private func addOptionalContexts(to result: inout [String: Any]) {
        if let prevSessionContext = self.prevSessionContext {
            result[Keys.prevSession.rawValue] = prevSessionContext.getPrevSessionDictionary()
        }
    }

    private mutating func addConditionalContexts(to result: inout [String: Any]) {
        if eventContext.type == CoralogixEventType.error {
            result[Keys.errorContext.rawValue] = self.errorContext.getDictionary()
            if let snapshotContext = self.snapshotContext {
                self.addSnapshotContext(to: &result)
            }
        }
        
        if eventContext.type == CoralogixEventType.navigation, self.snapshotContext != nil {
            self.addSnapshotContext(to: &result)
        }
        
        if isOneMinuteFromLastSnapshotPass == true, self.snapshotContext != nil {
            self.addSnapshotContext(to: &result)
            self.isOneMinuteFromLastSnapshotPass = false
        }
        
        if eventContext.type == CoralogixEventType.networkRequest {
            result[Keys.networkRequestContext.rawValue] = self.eventTypeContext.getDictionary()
        }
        
        if eventContext.type == CoralogixEventType.log {
            result[Keys.logContext.rawValue] = self.logContext.getDictionary()
        }
        
        if eventContext.type == CoralogixEventType.userInteraction,
           let interactionContext = self.interactionContext {
            result[Keys.interactionContext.rawValue] = interactionContext.getDictionary()
        }
    }
    
    private func addViewManagerContext(to result: inout [String: Any]) {
        if let viewManager = self.viewManager {
            if self.sessionContext?.isPidEqualToOldPid != nil {
                result[Keys.viewContext.rawValue] = viewManager.getPrevDictionary()
            } else {
                result[Keys.viewContext.rawValue] = viewManager.getDictionary()
            }
        }
    }
    
    private func addLabels(to result: inout [String: Any]) {
        if let labels = self.labels {
            result[Keys.labels.rawValue] = labels
        }
    }
    
    func addSnapshotContext(to result: inout [String: Any]) {
        if let snapshotContext = self.snapshotContext {
            result[Keys.isSnapshotEvent.rawValue] = true
            result[Keys.snapshotContext.rawValue] = snapshotContext.getDictionary()
            // Update lastTimestamp to now
            self.sessionManager?.lastSnapshotEventTime = Date()
        }
    }
}
