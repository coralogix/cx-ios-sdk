//
//  SessionContext.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import CoralogixInternal

struct SessionContext {
    let sessionId: String
    let sessionCreationDate: TimeInterval
    let operatingSystem: String
    let osVersion: String
    let device: String
    let userId: String
    let userName: String
    let userEmail: String
    let userMetadata: [String: String]?
    var isPidEqualToOldPid: Bool = false
    var hasRecording: Bool = false
    
    init(otel: SpanDataProtocol,
         sessionMetadata: SessionMetadata,
         userMetadata: [String: String]?,
         hasRecording: Bool = false) {
      if let pid = otel.getAttribute(forKey: Keys.pid.rawValue) as? String,
           let oldPid = sessionMetadata.oldPid,
           pid == oldPid,
           let oldSessionId = sessionMetadata.oldSessionId,
           let oldSessionCreationDate = sessionMetadata.oldSessionTimeInterval {
            self.sessionId = oldSessionId
            self.sessionCreationDate = oldSessionCreationDate
            self.isPidEqualToOldPid = true
        } else {
            self.sessionId = sessionMetadata.sessionId
            self.sessionCreationDate = sessionMetadata.sessionCreationDate
        }
        self.operatingSystem = Global.getOs()
        self.osVersion = Global.osVersionInfo()
        self.device = Global.getDeviceModel()
        self.userId = otel.getAttribute(forKey: Keys.userId.rawValue) as? String ?? ""
        self.userName = otel.getAttribute(forKey: Keys.userName.rawValue) as? String ?? ""
        self.userEmail = otel.getAttribute(forKey: Keys.userEmail.rawValue) as? String ?? ""
        self.userMetadata = userMetadata
        self.hasRecording = hasRecording
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        
        result[Keys.sessionId.rawValue] = self.sessionId
        result[Keys.sessionCreationDate.rawValue] = self.sessionCreationDate.milliseconds
        result[Keys.operatingSystem.rawValue] = self.operatingSystem
        result[Keys.osVersion.rawValue] = self.osVersion
        result[Keys.device.rawValue] = self.device
        result[Keys.userId.rawValue] = self.userId
        result[Keys.userName.rawValue] = self.userName
        result[Keys.userEmail.rawValue] = self.userEmail
        result[Keys.hasRecording.rawValue] = self.hasRecording
        if let userMetadata = self.userMetadata {
            result[Keys.userMetadata.rawValue] = userMetadata
        }
        return result
    }
    
    func getPrevSessionDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.sessionId.rawValue] = self.sessionId
        result[Keys.sessionCreationDate.rawValue] = self.sessionCreationDate.milliseconds
        return result
    }
}
