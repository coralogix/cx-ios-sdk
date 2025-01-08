//
//  CoralogixRum.swift
//  
//
//  Created by Tomer Har Yoffi on 03/11/2024.
//

import Foundation
import Coralogix_Internal

extension CoralogixRum {
    func initializeSessionReplay() {
        if let sessionId = self.sessionManager.getSessionMetadata()?.sessionId {
            
        }
        
        self.sessionManager.sessionChangedCallback = { sessionId in
            Log.d("[Session Id: \(sessionId)]")
        }
    }
    
    public func startRecording() {
        if let sessionId = self.sessionManager.getSessionMetadata()?.sessionId {
             //   sessionReplay.startSessionRecording()
        } else {
            Log.e("[Session Replay] failed to start recording - missing session id")
        }
    }
    
    public func stopRecording() {
//sessionReplay.stopSessionRecording()
    }
    
    public func captureEvent() {
         //   sessionReplay.captureEvent()
    }
}
