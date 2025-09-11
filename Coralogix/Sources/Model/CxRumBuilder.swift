//
//  CxRumBuilder.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 10/09/2025.
//

import Foundation

class CxRumBuilder {
    private let otel: SpanDataProtocol
    private let versionMetadata: VersionMetadata
    private let sessionManager: SessionManager
    private let viewManager: ViewManager
    private let networkManager: NetworkProtocol
    private let options: CoralogixExporterOptions
    
    // MARK: - Initializer
    
    init(otel: SpanDataProtocol,
         versionMetadata: VersionMetadata,
         sessionManager: SessionManager,
         viewManager: ViewManager,
         networkManager: NetworkProtocol,
         options: CoralogixExporterOptions) {
        self.otel = otel
        self.versionMetadata = versionMetadata
        self.sessionManager = sessionManager
        self.viewManager = viewManager
        self.networkManager = networkManager
        self.options = options
    }
    
    func build() -> CxRum {
        let eventContext = EventContext(otel: otel)
        
        updateSessionCounters(for: eventContext)
        
        let snapshotContext = buildSnapshotContextIfNeeded(for: eventContext)
        let internalContext = buildInternalContext(for: eventContext)
        
        let traceContext = Helper.getTraceAndSpanId(otel: otel)
        let userMetadata = options.userContext?.userMetadata
        let hasRecording = sessionManager.doesSessionhasRecording()
        
        return CxRum(timeStamp: otel.getStartTime() ?? Date().timeIntervalSince1970,
                     networkRequestContext: NetworkRequestContext(otel: otel),
                     versionMetadata: versionMetadata,
                     sessionContext: sessionManager.getSessionMetadata().map { SessionContext(otel: otel, sessionMetadata: $0, userMetadata: userMetadata, hasRecording: hasRecording) },
                     prevSessionContext: sessionManager.getPrevSessionMetadata().map { SessionContext(otel: otel, sessionMetadata: $0, userMetadata: userMetadata, hasRecording: hasRecording) },
                     eventContext: eventContext,
                     logContext: LogContext(otel: otel),
                     mobileSDK: CoralogixRum.mobileSDK,
                     environment: otel.getAttribute(forKey: Keys.environment.rawValue) as? String ?? "",
                     traceId: traceContext.traceId,
                     spanId: traceContext.spanId,
                     errorContext: ErrorContext(otel: otel),
                     deviceContext: DeviceContext(otel: otel),
                     deviceState: DeviceState(networkManager: networkManager),
                     labels: Helper.getLabels(otel: otel, labels: options.labels),
                     snapshotContext: snapshotContext,
                     interactionContext: InteractionContext(otel: otel),
                     mobileVitalsContext: MobileVitalsContext(otel: otel),
                     lifeCycleContext: LifeCycleContext(otel: otel),
                     screenShotContext: ScreenshotContext(otel: otel),
                     internalContext: internalContext,
                     fingerPrint: FingerprintManager(using: KeychainManager()).fingerprint
        )
    }
    
    private func updateSessionCounters(for eventContext: EventContext) {
        if eventContext.type == .userInteraction {
            sessionManager.incrementClickCounter()
        }
    }
    
    private func buildInternalContext(for eventContext: EventContext) -> InternalContext? {
        if eventContext.type == .internalKey {
            return InternalContext(eventName: Keys.initKey.rawValue, options: options)
        }
        return nil
    }
    
    internal func buildSnapshotContextIfNeeded(for eventContext: EventContext) -> SnapshotContext? {
        let currentTime = otel.getStartTime() ?? Date().timeIntervalSince1970
        let isErrorSeverity = eventContext.severity == CoralogixLogSeverity.error.rawValue
        let isNavigationEvent = eventContext.type == .navigation
        let oneMinuteHasPassed = sessionManager.lastSnapshotEventTime.map {
            abs($0.timeIntervalSince1970 - currentTime) > 60
        } ?? false
        
        // Check if any of the conditions for creating a snapshot are met
        if isErrorSeverity || isNavigationEvent || oneMinuteHasPassed {
            
            if isErrorSeverity {
                sessionManager.incrementErrorCounter()
            }
            
            sessionManager.lastSnapshotEventTime = Date()
            
            return SnapshotContext(
                timestamp: Date().timeIntervalSince1970,
                errorCount: sessionManager.getErrorCount(),
                viewCount: viewManager.getUniqueViewCount(),
                actionCount: sessionManager.getClickCount(),
                hasRecording: sessionManager.hasRecording
            )
        }
        return nil
    }
}
