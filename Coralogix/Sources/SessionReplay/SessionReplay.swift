//
//  CoralogixRum.swift
//  
//
//  Created by Tomer Har Yoffi on 03/11/2024.
//

import Foundation
import Coralogix_Internal

extension CoralogixRum: CoralogixInterface {
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
        }
    }
    
    public func startRecording() {
        if let sessionReplay = SdkManager.shared.getSessionReplay() {
            sessionReplay.startRecording()
            sessionReplay.captureEvent(name: "TestEvent", properties: ["key": "value"])
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
            sessionReplay.captureEvent(name: "TestEvent", properties: ["key": "value"])
        } else {
            Log.e("[SessionReplay] is not initialized")
        }
    }
}
