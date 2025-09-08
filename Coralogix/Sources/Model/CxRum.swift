//
//  CxRum.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import CoralogixInternal

struct CxRum {
    var timeStamp: TimeInterval
    let networkRequestContext: NetworkRequestContext
    let versionMetadata: VersionMetadata
    var sessionContext: SessionContext?
    var prevSessionContext: SessionContext?
    var networkManager: NetworkProtocol?
    var sessionManager: SessionManager?
    let eventContext: EventContext
    let logContext: LogContext
    let mobileSDK: MobileSDK
    let environment: String
    var traceId: String = ""
    var spanId: String = ""
    let errorContext: ErrorContext
    let deviceContext: DeviceContext
    let deviceState: DeviceState
    let viewContext: String? = nil
    var labels: [String: Any]?
    var viewManager: ViewManager?
    var snapshotContext: SnapshotContext?
    var isOneMinuteFromLastSnapshotPass = false
    var interactionContext: InteractionContext?
    var mobileVitalsContext: MobileVitalsContext?
    var lifeCycleContext: LifeCycleContext?
    var screenShotContext: ScreenshotContext?
    var internalContext: InternalContext?
    var fingerPrint: String = ""
     
    init(otel: SpanDataProtocol,
         versionMetadata: VersionMetadata,
         sessionManager: SessionManager,
         viewManager: ViewManager,
         networkManager: NetworkProtocol,
         metricsManager: MetricsManager,
         options: CoralogixExporterOptions) {

        self.networkRequestContext = NetworkRequestContext(otel: otel)
        self.errorContext = ErrorContext(otel: otel)
        self.deviceContext = DeviceContext(otel: otel)
        self.logContext = LogContext(otel: otel)
        self.deviceState = DeviceState(networkManager: self.networkManager)
        self.interactionContext = InteractionContext(otel: otel)
        self.mobileVitalsContext = MobileVitalsContext(otel: otel)
        self.lifeCycleContext = LifeCycleContext(otel: otel)
        self.eventContext = EventContext(otel: otel)
        self.screenShotContext = ScreenshotContext(otel: otel)
        
        self.timeStamp = otel.getStartTime() ?? Date().timeIntervalSince1970
        self.environment = otel.getAttribute(forKey: Keys.environment.rawValue) as? String ?? ""

        self.versionMetadata = versionMetadata
        self.sessionManager = sessionManager
        self.networkManager = networkManager
        self.viewManager = viewManager
        self.labels = options.labels
        self.fingerPrint = FingerprintManager(using: KeychainManager()).fingerprint

        self.mobileSDK = CoralogixRum.mobileSDK

        let traceContext = Helper.getTraceAndSpanId(otel: otel)
        self.traceId = traceContext.traceId
        self.spanId = traceContext.spanId
        let userMetadata = options.userContext?.userMetadata
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
        self.updateSnapshotContextIfNeeded(for: eventContext)
        
        // Check for User Interaction
        if eventContext.type.rawValue == CoralogixEventType.userInteraction.rawValue {
            sessionManager.incrementClickCounter()
        }
        
        if eventContext.type.rawValue == CoralogixEventType.internalKey.rawValue {
            self.internalContext = InternalContext(eventName: Keys.initKey.rawValue, options: options)
        }
    }
    
    internal mutating func updateSnapshotContextIfNeeded(for eventContext: EventContext) {
        guard let sessionManager = self.sessionManager,
              let viewManager = self.viewManager else {
            return
        }
                
        // Check if more than 1 minute passed since last snapshot
        if let lastSnapshotSent = sessionManager.lastSnapshotEventTime,
           isMoreThanOneMinuteDifference(interval1: lastSnapshotSent.timeIntervalSince1970, interval2: self.timeStamp) {
            
            self.snapshotContext = buildSnapshotContext(sessionManager: sessionManager, viewManager: viewManager)
            self.isOneMinuteFromLastSnapshotPass = true
        }
        
        // Check for error severity
        if eventContext.severity == CoralogixLogSeverity.error.rawValue {
            sessionManager.incrementErrorCounter()
            self.snapshotContext = buildSnapshotContext(sessionManager: sessionManager, viewManager: viewManager)
        }
        
        // Check for navigation event
        if eventContext.type.rawValue == CoralogixEventType.navigation.rawValue {
            self.snapshotContext = buildSnapshotContext(sessionManager: sessionManager, viewManager: viewManager)
        }
    }
    
    internal func buildSnapshotContext(sessionManager: SessionManager, viewManager: ViewManager) -> SnapshotContext {
        return SnapshotContext(
            timestamp: Date().timeIntervalSince1970,
            errorCount: sessionManager.getErrorCount(),
            viewCount: viewManager.getUniqueViewCount(),
            actionCount: sessionManager.getClickCount(),
            hasRecording: sessionManager.hasRecording
        )
    }
    
    internal func isMoreThanOneMinuteDifference(interval1: TimeInterval, interval2: TimeInterval) -> Bool {
        let difference = abs(interval1 - interval2)
        return difference > 60
    }

    mutating func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        self.addBasicDetails(to: &result)
        self.addConditionalContexts(to: &result)
        self.addViewManagerContext(to: &result)
        self.addLabels(to: &result)
        return result
    }

    private func addLifeCycleContext(to result: inout [String: Any]) {
        result[Keys.lifeCycleContext.rawValue] = self.lifeCycleContext?.getLifeCycleDictionary()
    }
    
    private func addMobileVitals(to result: inout [String: Any]) {
        if let mobileVitalsContext = self.mobileVitalsContext {
            result[Keys.mobileVitalsContext.rawValue] = mobileVitalsContext.getMobileVitalsDictionary()
        }
    }
    
    private func addBasicDetails(to result: inout [String: Any]) {
        result[Keys.fingerPrint.rawValue] = self.fingerPrint
        result[Keys.timestamp.rawValue] = self.timeStamp.milliseconds
        result[Keys.mobileSdk.rawValue] = self.mobileSDK.getDictionary()
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

    private mutating func addConditionalContexts(to result: inout [String: Any]) {
        if eventContext.type == CoralogixEventType.error {
            result[Keys.errorContext.rawValue] = self.errorContext.getDictionary()
        }
                
        if let screenShotContext = self.screenShotContext, screenShotContext.isValid() {
            result[Keys.screenshotContext.rawValue] = screenShotContext.getDictionary()
        }
        
        if eventContext.type == CoralogixEventType.networkRequest {
            result[Keys.networkRequestContext.rawValue] = self.networkRequestContext.getDictionary()
        }
        
        if eventContext.type == CoralogixEventType.mobileVitals {
            self.addMobileVitals(to: &result)
        }
        
        if eventContext.type == CoralogixEventType.lifeCycle {
            self.addLifeCycleContext(to: &result)
        }
        
        if eventContext.type == CoralogixEventType.log {
            result[Keys.logContext.rawValue] = self.logContext.getDictionary()
        }
        
        if eventContext.type == CoralogixEventType.userInteraction,
           let interactionContext = self.interactionContext {
            result[Keys.interactionContext.rawValue] = interactionContext.getDictionary()
        }
        
        if let prevSessionContext = self.prevSessionContext {
            result[Keys.prevSession.rawValue] = prevSessionContext.getPrevSessionDictionary()
        }
        
        if isOneMinuteFromLastSnapshotPass == true, self.snapshotContext != nil {
            self.isOneMinuteFromLastSnapshotPass = false
        }
                
        if self.snapshotContext != nil {
            self.addSnapshotContext(to: &result)
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
