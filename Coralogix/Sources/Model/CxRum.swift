//
//  CxRum.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import CoralogixInternal

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
    var lifeCycleContext: LifeCycleContext?
    var screenshotId: String?
    var page: Int?
     
    init(otel: SpanDataProtocol,
         versionMetadata: VersionMetadata,
         sessionManager: SessionManager,
         viewManager: ViewManager,
         networkManager: NetworkProtocol,
         metricsManager: MetricsManager,
         userMetadata: [String: String]?,
         labels: [String: Any]?) {

        self.timeStamp = otel.getStartTime() ?? Date().timeIntervalSince1970
        self.eventTypeContext = EventTypeContext(otel: otel)
        self.mobileSdk = Global.sdk.rawValue
        self.versionMetadata = versionMetadata
        self.sessionManager = sessionManager
        self.networkManager = networkManager
        self.viewManager = viewManager
        let hasRecording = sessionManager.doesSessionhasRecording()

        if let sessionMetadata = sessionManager.getSessionMetadata() {
            self.sessionContext = SessionContext(otel: otel,
                                                 sessionMetadata: sessionMetadata,
                                                 userMetadata: userMetadata,
                                                 hasRecording: hasRecording)
            if let prevSessionMetadata = sessionManager.getPrevSessionMetadata() {
                self.prevSessionContext = SessionContext(otel: otel,
                                                         sessionMetadata: prevSessionMetadata,
                                                         userMetadata: userMetadata,
                                                         hasRecording: hasRecording)
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
        self.snapshotContext = SnapshotConext.getSnapshot(otel: otel, sessionManager: self.sessionManager)
        self.interactionContext = InteractionContext(otel: otel)
        self.mobileVitalsContext = MobileVitalsContext(otel: otel)
        self.lifeCycleContext = LifeCycleContext(otel: otel)
        self.screenshotId = otel.getAttribute(forKey: Keys.screenshotId.rawValue) as? String
        self.page = otel.getAttribute(forKey: Keys.page.rawValue) as? Int ?? 0
        
        if let sessionManager = self.sessionManager,
           let viewManager = self.viewManager,
           let lastSnapshotSent = sessionManager.lastSnapshotEventTime {
            if isMoreThanOneMinuteDifference(interval1: lastSnapshotSent.timeIntervalSince1970, interval2: self.timeStamp) {
                self.snapshotContext = SnapshotConext(timestemp: Date().timeIntervalSince1970,
                                                      errorCount: sessionManager.getErrorCount(),
                                                      viewCount: viewManager.getUniqueViewCount(),
                                                      clickCount: sessionManager.getClickCount(),
                                                      hasRecording: sessionManager.hasRecording)
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
        self.addLifeCycleContext(to: &result)
        self.addScreenshotContext(to: &result)
        return result
    }
    
    internal func addScreenshotContext(to result: inout [String: Any]) {
        if let screenshotId = self.screenshotId, let page = self.page {
            var screenshotContext = [String: Any]()
            screenshotContext[Keys.screenshotId.rawValue] = screenshotId
            screenshotContext[Keys.page.rawValue] = page
            screenshotContext[Keys.segmentTimestamp.rawValue] = self.timeStamp.milliseconds
            
            result[Keys.screenshotContext.rawValue] = screenshotContext
        }
    }

    private func addLifeCycleContext(to result: inout [String: Any]) {
        result[Keys.lifeCycleContext.rawValue] = self.lifeCycleContext?.getLifeCycleDictionary()
    }
    
    private func addMobileVitals(to result: inout [String: Any]) {
        if let mobileVitalsDictionary = self.mobileVitalsContext?.getMobileVitalsDictionary(),
           !Helper.isEmptyDictionary(mobileVitalsDictionary) {
            result[Keys.mobileVitalsContext.rawValue] = self.mobileVitalsContext?.getMobileVitalsDictionary()
        }
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
            if self.snapshotContext != nil {
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
            if let sessionContext = self.sessionContext,
               sessionContext.isPidEqualToOldPid == true {
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
