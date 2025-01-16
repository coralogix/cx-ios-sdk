//
//  CoralogixRum.swift
//  
//
//  Created by Coralogix DEV TEAM on 03/11/2024.
//

import Foundation
import Coralogix_Internal

extension CoralogixRum: CoralogixInterface {
    public func getSessionCreationTimestamp() -> TimeInterval {
        return self.sessionManager.getSessionMetadata()?.sessionCreationDate ?? 0
    }
    
    public func getApplication() -> String {
        return self.options?.application ?? ""
    }
    
    public func getCoralogixDomain() -> String {
        if let customDomainUrl = self.options?.customDomainUrl,
           self.options?.customDomainUrl != "" {
            return "\(customDomainUrl)"
        } else {
            return self.options?.coralogixDomain.rawValue ?? ""
        }
    }
    
    public func getPublicKey() -> String {
        return self.options?.publicKey ?? ""
    }
    
    public func getSessionID() -> String {
        return self.sessionManager.getSessionMetadata()?.sessionId ?? ""
    }
    
    public func reportError(_ error: String) {
        Log.d("[SessionRelay] Reporting error: \(error)")
    }
    
    func initializeSessionReplay() {
        SdkManager.shared.register(coralogixInterface: self)
        
        self.sessionManager.sessionChangedCallback = { sessionId in
            Log.d("[Session Id: \(sessionId)]")
            
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
            sessionReplay.captureEvent(properties: ["key": "value"])
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
        if let sessionReplay = SdkManager.shared.getSessionReplay() {
            sessionReplay.captureEvent(properties: ["key": "value"])
        } else {
            Log.e("[SessionReplay] is not initialized")
        }
    }
}
