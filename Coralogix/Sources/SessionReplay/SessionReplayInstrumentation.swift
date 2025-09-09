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
        Log.d("[SessionRelay] Reporting error: \(error)")
    }
    
    public func initializeSessionReplay() {
        SdkManager.shared.register(coralogixInterface: self)
        
        self.sessionManager?.sessionChangedCallback = { sessionId in
            Log.d("[Changed Session Id: \(sessionId)]")
            
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
    
    internal func makeSpan(isManual: Bool = false) {
        var span = makeSpan(event: .screenshot, source: .console, severity: .info)
        self.addScreenshotId(to: &span)
        if isManual { span.setAttribute(key: Keys.isManual.rawValue, value: AttributeValue(true)) }
        span.end()
    }
    
    public func isIdle() -> Bool {
        return self.coralogixExporter?.getSessionManager().isIdle ?? false
    }
}
