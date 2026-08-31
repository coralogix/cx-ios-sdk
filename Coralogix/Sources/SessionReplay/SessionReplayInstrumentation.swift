//
//  CoralogixRum.swift
//  
//
//  Created by Coralogix DEV TEAM on 03/11/2024.
//

import Foundation
import CoralogixInternal

extension CoralogixRum: CoralogixInterface {
    public func periodicallyCaptureEventTriggered() {
        self.makeSpan()
    }
    
    public func hasSessionRecording(_ hasSessionRecording: Bool) {
        self.sessionManager?.hasRecording = hasSessionRecording
    }
    
    public func isDebug() -> Bool {
        return self.options?.debug ?? false
    }
    
    public func getSessionCreationTimestamp() -> TimeInterval {
        return self.sessionManager?.getSessionMetadata()?.sessionCreationDate ?? 0
    }
    
    public func getApplication() -> String {
        return self.options?.application ?? ""
    }
    
    public func getCoralogixDomain() -> String {
        return self.options?.coralogixDomain.rawValue ?? ""
    }
    
    public func getProxyUrl() -> String {
        return self.options?.proxyUrl ?? ""
    }
    
    public func getPublicKey() -> String {
        return self.options?.publicKey ?? ""
    }
    
    public func getSessionID() -> String {
        return self.sessionManager?.getSessionMetadata()?.sessionId ?? ""
    }
    
    public func reportError(_ error: String) {
        // Error reported to session replay
    }
    
    public func initializeSessionReplay() {
        SdkManager.shared.register(coralogixInterface: self)
        
        self.sessionManager?.sessionChangedCallback = { sessionId in
            guard let sessionReplay = SdkManager.shared.getSessionReplay() else {
                Log.e("Failed to get Session Recording ")
                return
            }
            sessionReplay.update(sessionId: sessionId)
        }
    }
    
    public func startRecording() {
        if let sessionReplay = SdkManager.shared.getSessionReplay() {
            sessionReplay.startRecording()
        } else {
            Log.e("[SessionReplay] is not initialized")
        }
    }
    
    public func stopRecording() {
        if let sessionReplay = SdkManager.shared.getSessionReplay() {
            sessionReplay.stopRecording()
        } else {
            Log.e("[SessionReplay] is not initialized")
        }
    }
    
    public func captureEvent() {
        self.makeSpan(isManual: true)
    }
    
    public func isSRRecording() -> Bool {
        if let sessionReplay = SdkManager.shared.getSessionReplay() {
            return sessionReplay.isRecording()
        }
        return false
    }
    
    public func isSRInitialized() -> Bool {
        if let sessionReplay = SdkManager.shared.getSessionReplay() {
            return sessionReplay.isInitialized()
        }
        return false
    }
    
    public func update(sessionId: String) {
        guard let sessionReplay = SdkManager.shared.getSessionReplay() else {
            Log.e("Failed to get Session Recording ")
            return
        }
        sessionReplay.update(sessionId: sessionId)
    }
    
    internal func makeSpan(isManual: Bool = false) {
        let span = makeSpan(event: .screenshot, source: .console, severity: .info)
        if isManual { span.setAttribute(key: Keys.isManual.rawValue, value: AttributeValue(true)) }
        // A screenshot span exists only to point at a frame, so a dropped capture emits no span
        // at all — the same rule Android applies, where the screenshot log is reported only for a
        // frame that shipped. `isManual` travels with the capture so the host's own
        // `captureEvent()` is not deduplicated away: it asked for this frame explicitly.
        let extra: [String: Any] = isManual ? [Keys.isManual.rawValue: true] : [:]
        self.recordScreenshotForSpan(on: span, extraProperties: extra) { didCapture in
            guard didCapture else {
                Log.d("[SessionReplay] capture produced no frame — screenshot event not reported")
                return
            }
            span.end()
        }
    }
    
    public func isIdle() -> Bool {
        return self.coralogixExporter?.getSessionManager().isIdle ?? false
    }
    
    public func getNextScreenshotLocationProperties() -> [String: Any] {
        guard let screenshotManager = self.coralogixExporter?.getScreenshotManager() else {
            Log.e("[CoralogixRum] ScreenshotManager not available")
            return [:]
        }
        return screenshotManager.nextScreenshotLocation.toProperties()
    }
    
    public func revertScreenshotCounter() {
        self.coralogixExporter?.getScreenshotManager().revertScreenshotCounter()
    }

    public func revertScreenshotCounter(page: Int, segmentIndex: Int) {
        let location = ScreenshotLocation(segmentIndex: segmentIndex, page: page, screenshotId: "")
        self.coralogixExporter?.getScreenshotManager().revertScreenshotCounter(for: location)
    }

    public func reportSessionReplayInit(snapshot: [String: Any]) {
        self.createSessionReplayInitSpan(snapshot: snapshot)
    }
}
