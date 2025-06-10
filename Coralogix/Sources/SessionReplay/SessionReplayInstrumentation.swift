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
        if let sessionReplay = SdkManager.shared.getSessionReplay() {
            let screenshotId = UUID().uuidString.lowercased()
            let properties: [String: Any] = [
                Keys.screenshotId.rawValue: screenshotId
            ]
            sessionReplay.captureEvent(properties: properties)
        } else {
            Log.e("[SessionReplay] is not initialized")
        }
    }
    
    public func hasSessionRecording(_ hasSessionRecording: Bool) {
        self.sessionManager?.hasRecording = hasSessionRecording
    }
    
    public func isDebug() -> Bool {
        return self.coralogixExporter?.getOptions().debug ?? false
    }
    
    public func getSessionCreationTimestamp() -> TimeInterval {
        return self.sessionManager?.getSessionMetadata()?.sessionCreationDate ?? 0
    }
    
    public func getApplication() -> String {
        return self.coralogixExporter?.getOptions().application ?? ""
    }
    
    public func getCoralogixDomain() -> String {
        return self.coralogixExporter?.getOptions().coralogixDomain.rawValue ?? ""
    }
    
    public func getPublicKey() -> String {
        return self.coralogixExporter?.getOptions().publicKey ?? ""
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
    
    public func captureEvent(properties: [String: Any] = [:]) {
        if let sessionReplay = SdkManager.shared.getSessionReplay() {
            sessionReplay.captureEvent(properties: properties)
        } else {
            Log.e("[SessionReplay] is not initialized")
        }
    }
}
