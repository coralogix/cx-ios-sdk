//
//  CxSpan.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import OpenTelemetrySdk

public class CxSpan {
    let versionMetadata: VersionMetadata
    let applicationName: String
    let subsystemName: String
    let isErrorWithStacktrace: Bool = false
    var severity: Int = 0
    var timeStamp: TimeInterval = 0
    let cxRum: CxRum
    
    init(otel: SpanDataProtocol,
         versionMetadata: VersionMetadata,
         sessionManager: SessionManager,
         networkManager: NetworkProtocol,
         viewManager: ViewManager,
         userMetadata: [String: String]?,
         labels: [String: Any]?) {
        self.applicationName = versionMetadata.appName
        self.versionMetadata = versionMetadata
        self.subsystemName = Keys.cxRum.rawValue
        if let severity = otel.getAttribute(forKey: Keys.severity.rawValue) as? String {
            self.severity = Int(severity) ?? 0
        }
        self.timeStamp = otel.getStartTime() ?? Date().timeIntervalSince1970
        self.cxRum = CxRum(otel: otel,
                           versionMetadata: versionMetadata,
                           sessionManager: sessionManager,
                           viewManager: viewManager,
                           networkManager: networkManager,
                           userMetadata: userMetadata,
                           labels: labels)
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.versionMetaData.rawValue] = versionMetadata.getDictionary()
        result[Keys.applicationName.rawValue] = self.applicationName
        result[Keys.subsystemName.rawValue] = self.subsystemName
        result[Keys.severity.rawValue] = self.severity
        result[Keys.timestamp.rawValue] = self.timeStamp.milliseconds
        result[Keys.text.rawValue] = [Keys.cxRum.rawValue: self.cxRum.getDictionary()]
        return result
    }
}

public struct VersionMetadata {
    let appName: String
    let appVersion: String
    
    func getDictionary() -> [String: Any] {
        return [Keys.appName.rawValue: self.appName, Keys.appVersion.rawValue: self.appVersion]
    }
}


protocol KeyChainProtocol {
    func readStringFromKeychain(service: String, key: String) -> String?
    func writeStringToKeychain(service: String, key: String, value: String)
}

public struct SessionMetadata {
    var sessionId: String
    var sessionCreationDate: TimeInterval
    var oldPid: String?
    var oldSessionId: String?
    var oldSessionTimeInterval: TimeInterval?
    var keyChain: KeyChainProtocol?
    
    init(sessionId: String, sessionCreationDate: TimeInterval, keychain: KeyChainProtocol) {
        self.sessionId = sessionId
        self.sessionCreationDate = sessionCreationDate
        self.keyChain = keychain
        self.loadPrevSession()
    }
    
    mutating func resetSessionMetadata() {
        self.sessionId = ""
        self.sessionCreationDate = 0
    }
    
    mutating func loadPrevSession() {
        let newPid = getpid()
        
        if let oldPid = keyChain?.readStringFromKeychain(service: Keys.service.rawValue, 
                                                         key: Keys.pid.rawValue),
           let oldSessionId = keyChain?.readStringFromKeychain(service: Keys.service.rawValue,
                                                               key: Keys.keySessionId.rawValue),
           let oldSessionTimeInterval = keyChain?.readStringFromKeychain(service: Keys.service.rawValue,
                                                                         key: Keys.keySessionTimeInterval.rawValue) {
            Log.d("OLD Process ID:\(oldPid)")
            Log.d("OLD Session ID:\(oldSessionId)")
            Log.d("OLD Session TimeInterval:\(oldSessionTimeInterval)")
            self.oldPid = oldPid
            self.oldSessionId = oldSessionId
            self.oldSessionTimeInterval = TimeInterval(oldSessionTimeInterval)
        }
        
        Log.d("NEW Process ID:\(newPid)")
        Log.d("NEW Session ID:\(sessionId)")
        Log.d("NEW Session TimeInterval:\(sessionCreationDate)")

        keyChain?.writeStringToKeychain(service: Keys.service.rawValue,
                                        key: Keys.pid.rawValue,
                                        value: String(newPid))
        keyChain?.writeStringToKeychain(service: Keys.service.rawValue,
                                        key: Keys.keySessionId.rawValue,
                                        value: sessionId)
        keyChain?.writeStringToKeychain(service: Keys.service.rawValue,
                                        key: Keys.keySessionTimeInterval.rawValue,
                                        value: String(sessionCreationDate))
    }
}
