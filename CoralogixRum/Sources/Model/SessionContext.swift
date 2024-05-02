//
//  SessionContext.swift
//  Elastiflix-iOS
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi

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
    
    init(otel: SpanData, versionMetadata: VersionMetadata, sessionMetadata: SessionMetadata, userMetadata: [String: String]?) {
        if let pid = otel.attributes[Keys.pid.rawValue]?.description,
           let oldPid = sessionMetadata.oldPid,
           pid == oldPid,
           let oldSessionId = sessionMetadata.oldSessionId,
           let oldSessionCreationDate = sessionMetadata.oldSessionTimeInterval {
            self.sessionId = oldSessionId
            self.sessionCreationDate = oldSessionCreationDate
        } else {
            self.sessionId = sessionMetadata.sessionId
            self.sessionCreationDate = sessionMetadata.sessionCreationDate
        }
        self.operatingSystem = Global.getOs()
        self.osVersion = Global.osVersionInfo()
        self.device = Global.getDeviceModel()
        self.userId = otel.attributes[Keys.userId.rawValue]?.description ?? ""
        self.userName = otel.attributes[Keys.userName.rawValue]?.description ?? ""
        self.userEmail = otel.attributes[Keys.userEmail.rawValue]?.description ?? "" 
        self.userMetadata = userMetadata
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
