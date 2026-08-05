//
//  CxRumBuilder.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 10/09/2025.
//

import Foundation
import CoralogixInternal

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
    
    func build() -> CxRum? {
        let eventContext = EventContext(otel: otel)
        
        updateSessionCounters(for: eventContext)

        let internalContext = buildInternalContext(for: eventContext)
        
        let traceContext = Helper.getTraceAndSpanId(otel: otel)
        let userMetadata = options.userContext?.userMetadata
        let hasRecording = sessionManager.doesSessionHasRecording()
        var timeStamp = otel.getStartTime() ?? Date().timeIntervalSince1970
        var prevSessionContext: SessionContext? = nil
        
        // CRITICAL: If SessionContext creation fails (missing session attributes), drop the span
        guard var sessionContext = SessionContext(otel: otel,
                                                  userMetadata: userMetadata,
                                                  hasRecording: hasRecording) else {
            Log.w("[CxRumBuilder] Dropping span due to missing session attributes")
            return nil
        }

        // Consumed only after the drop-guard above: a span that never exports must not
        // swallow the one-shot promotion armed by setUserContext. Taken unconditionally
        // (not short-circuited behind the other triggers) — browser parity: any emitted
        // snapshot satisfies the pending request. What keeps the one-shot alive is the
        // invariant that every path that does NOT emit the promoted snapshot hands the
        // token back: the eligibility reject below and the beforeSend drop in
        // CxSpan.getDictionary() are those paths today — any new early-out between the
        // take and the snapshot decision must do the same.
        var pendingSnapshotTrigger = sessionManager.consumePendingSnapshotTrigger()

        // Eligibility: the token only promotes a span of the session it was armed in
        // that started at or after the arm. A buffered span from a rotated-out session
        // would stamp the new session's identity onto the old session's snapshot
        // record; a pre-arm span describes a moment before the user change and already
        // went out through tracesExporter with the old identity. Either way, hand the
        // token back (session-checked) and leave this span unpromoted — the armed
        // session's next eligible event carries the promotion instead.
        if let trigger = pendingSnapshotTrigger,
           !trigger.canPromote(sessionId: sessionContext.sessionId,
                               spanStartTime: otel.getStartTime()) {
            sessionManager.restorePendingSnapshotTrigger(trigger)
            pendingSnapshotTrigger = nil
        }

        let snapshotContext = buildSnapshotContextIfNeeded(for: eventContext,
                                                           pendingTrigger: pendingSnapshotTrigger)

        // The promoted event reports the identity the token was armed with — the
        // carrier span's own identity can predate the setUserContext call (attributes
        // stamped at creation, options copied at encode). A nil token context records
        // a clear. prevSessionContext is left untouched: it describes the prior
        // session's historical identity.
        if let trigger = pendingSnapshotTrigger {
            sessionContext.applyUserContextOverride(trigger.userContext)
        }

        if SessionContext.shouldRestorePreviousSession(from: otel){
            // Note: prevSessionContext can be nil if session attributes are missing
            // This is acceptable - we'll use the current session instead
            prevSessionContext = SessionContext(otel: otel,
                                                userMetadata: userMetadata,
                                                hasRecording: hasRecording)
        }
        
        // Patch, in case of session creation date is bigger that log timeStamp
        if sessionContext.sessionCreationDate > timeStamp {
            timeStamp = sessionContext.sessionCreationDate
        }

        // Frozen view wins (native AND hybrid go through makeSpan → addViewMetadata); only
        // non-SDK spans lack it and fall back to the live ViewManager. view_number is frozen
        // alongside the name, so a present name means the frozen number is authoritative.
        let frozenViewName = otel.getAttribute(forKey: Keys.spanViewName.rawValue) as? String
        let frozenViewNumber = Self.frozenViewNumber(from: otel)
        let resolvedViewNumber = frozenViewName == nil ? viewManager.getViewNumber() : frozenViewNumber

        return CxRum(timeStamp: timeStamp,
                     networkRequestContext: NetworkRequestContext(otel: otel),
                     versionMetadata: versionMetadata,
                     sessionContext: sessionContext,
                     prevSessionContext: prevSessionContext,
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
                     consumedSnapshotTrigger: pendingSnapshotTrigger,
                     interactionContext: InteractionContext(otel: otel),
                     mobileVitalsContext: MobileVitalsContext(otel: otel),
                     lifeCycleContext: LifeCycleContext(otel: otel),
                     screenShotContext: ScreenshotContext(otel: otel),
                     internalContext: internalContext,
                     measurementContext: MeasurementContext(otel: otel),
                     fingerPrint: FingerprintManager(using: KeychainManager()).fingerprint,
                     // CX-44687: pure function of current event type — no cross-event state.
                     isNavigationEvent: eventContext.type == .navigation,
                     viewNumber: resolvedViewNumber,
                     viewName: frozenViewName
        )
    }

    /// `getAttribute` returns the `AttributeValue` String description; accept Int too for mocks.
    private static func frozenViewNumber(from otel: SpanDataProtocol) -> Int? {
        guard let raw = otel.getAttribute(forKey: Keys.spanViewNumber.rawValue) else { return nil }
        if let intValue = raw as? Int { return intValue }
        if let stringValue = raw as? String { return Int(stringValue) }
        return nil
    }
    
    private func updateSessionCounters(for eventContext: EventContext) {
        if eventContext.type == .userInteraction {
            sessionManager.incrementClickCounter()
        }
    }
    
    private func buildInternalContext(for eventContext: EventContext) -> InternalContext? {
        guard eventContext.type == .internalKey else { return nil }

        // session_replay_init carries its own snapshot as a span attribute (it lives in the
        // SessionReplay module, which the exporter can't reach). The SDK-init log carries no
        // sub-type attribute and reconstructs its payload from the live exporter options.
        // CX-44984 lesson #1: without this branch the span has the right attributes but
        // internal_context never lands on the wire.
        if let internalEventType = otel.getAttribute(forKey: Keys.internalEventType.rawValue) as? String,
           internalEventType == Keys.sessionReplayInit.rawValue {
            let data = (otel.getAttribute(forKey: Keys.internalEventData.rawValue) as? String)
                .flatMap { Helper.convertJsonStringToDict(jsonString: $0) } ?? [:]
            return InternalContext(eventName: internalEventType, data: data)
        }
        return InternalContext(eventName: Keys.initKey.rawValue, data: options.getInitData())
    }
    
    /// Decides whether this event emits a snapshot — and when it does, mutates session
    /// state (error counter, snapshot-throttle timestamp), so call it exactly once per
    /// event, at emit time; a speculative call over-counts errors and steals the next
    /// qualifying event's snapshot. The caller (`build()`) owns consuming the pending
    /// setUserContext trigger and passes the token in, so a span dropped before this
    /// point can never swallow the one-shot promotion.
    internal func buildSnapshotContextIfNeeded(for eventContext: EventContext,
                                               pendingTrigger: PendingSnapshotTrigger? = nil) -> SnapshotContext? {
        let currentTime = otel.getStartTime() ?? Date().timeIntervalSince1970
        let isErrorSeverity = eventContext.severity == CoralogixLogSeverity.error.rawValue
        let isNavigationEvent = eventContext.type == .navigation
        // nil means no snapshot has been emitted yet on this session (initial
        // launch or just-rotated), so treat the throttle as expired and emit
        // the next qualifying event. SessionManager.setupSessionMetadata()
        // relies on this to give the fresh session its first snapshot.
        let oneMinuteHasPassed = sessionManager.lastSnapshotEventTime.map {
            abs($0.timeIntervalSince1970 - currentTime) > 60
        } ?? true
        
        // Check if any of the conditions for creating a snapshot are met
        if isErrorSeverity || isNavigationEvent || oneMinuteHasPassed || pendingTrigger != nil {
            
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

