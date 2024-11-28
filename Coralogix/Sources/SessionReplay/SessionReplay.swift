//
//  File.swift
//  
//
//  Created by Tomer Har Yoffi on 03/11/2024.
//

import Foundation
import session_replay

extension CoralogixRum {
    func initializeSessionReplay() {
        if let sessionId = self.sessionManager.getSessionMetadata()?.sessionId {
            self.sessionReplay = SessionReplay(sessionId: sessionId, recordingType: .image) { message in
                Log.d(message)
            }
        }
        
        self.sessionManager.sessionChangedCallback = { sessionId in
            Log.d("[Session Id: \(sessionId)]")
        }
    }
    
    public func startRecording() {
        if let sessionId = self.sessionManager.getSessionMetadata()?.sessionId {
            if let sessionReplay = self.sessionReplay  {
                sessionReplay.startSessionRecording()
            }
        } else {
            Log.e("[Session Replay] failed to start recording - missing session id")
        }
    }
    
    public func stopRecording() {
        if let sessionReplay = self.sessionReplay {
            sessionReplay.stopSessionRecording()
        }
    }
    
    public func captureEvent() {
        if let sessionReplay = self.sessionReplay {
            sessionReplay.captureEvent()
        }
    }
}
