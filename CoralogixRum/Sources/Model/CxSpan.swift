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
    
    init(otelSpan: SpanDataProtocol,
         versionMetadata: VersionMetadata,
         sessionManager: SessionManager,
         userMetadata: [String: String]?,
         labels: [String: Any]?) {
        self.applicationName = versionMetadata.appName
        self.versionMetadata = versionMetadata
        self.subsystemName = Keys.cxRum.rawValue
        if let severity = otelSpan.getAttribute(forKey: Keys.severity.rawValue) as? String {
            self.severity = Int(severity) ?? 0
        }
        if let timeStamp = otelSpan.getStartTime() {
            self.timeStamp = timeStamp
        }
        self.cxRum = CxRum(otel: otelSpan,
                           versionMetadata: versionMetadata,
                           sessionManager: sessionManager,
                           userMetadata: userMetadata,
                           labels: labels)
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.versionMetaData.rawValue] = versionMetadata.getDictionary()
        result[Keys.applicationName.rawValue] = self.applicationName
        result[Keys.subsystemName.rawValue] = self.subsystemName
        result[Keys.severity.rawValue] =  self.severity
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

public struct SessionMetadata {
    var sessionId: String
    var sessionCreationDate: TimeInterval
    var oldPid: String?
    var oldSessionId: String?
    var oldSessionTimeInterval: TimeInterval?
    
    init(sessionId: String, sessionCreationDate: TimeInterval) {
        self.sessionId = sessionId
        self.sessionCreationDate = sessionCreationDate
        self.loadPrevSession()
    }
    
    mutating func resetSessionMetadata() {
        self.sessionId = ""
        self.sessionCreationDate = 0
    }
    
    mutating func loadPrevSession() {
        let service = "com.coralogix.sdk"
        let keyPid = "pid"
        let keySessionId = "sessionId"
        let keySessionTimeInterval =  "sessionTimeInterval"
        if let oldPid = self.readStringFromKeychain(service: service, key: keyPid),
           let oldSessionId = self.readStringFromKeychain(service: service, key: keySessionId),
           let oldSessionTimeInterval = self.readStringFromKeychain(service: service, key: keySessionTimeInterval) {
            Log.d("OLD Process ID:\(oldPid)")
            Log.d("OLD Session ID:\(oldSessionId)")
            Log.d("OLD Session TimeInterval:\(oldSessionTimeInterval)")
            self.oldPid = oldPid
            self.oldSessionId = oldSessionId
            self.oldSessionTimeInterval = TimeInterval(oldSessionTimeInterval)
        }
        
        let newPid = getpid()
        Log.d("NEW Process ID:\(newPid)")
        Log.d("NEW Session ID:\(sessionId)")
        Log.d("NEW Session TimeInterval:\(sessionCreationDate)")

        saveStringToKeychain(service: service, key: keyPid, value: String(newPid))
        saveStringToKeychain(service: service, key: keySessionId, value: sessionId)
        saveStringToKeychain(service: service, key: keySessionTimeInterval, value: String(sessionCreationDate))
    }
    
    // Function to read a string from Keychain
    private func readStringFromKeychain(service: String, key: String) -> String? {
        // Create the Keychain query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        
        // Retrieve the item from the Keychain
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let stringValue = String(data: data, encoding: .utf8) else {
            Log.e("Failed to read data from Keychain")
            return nil
        }
        
        return stringValue
    }
    
    // Function to save a string into Keychain
    private func saveStringToKeychain(service: String, key: String, value: String) {
        // Convert the string value to Data
        guard let data = value.data(using: .utf8) else {
            Log.e("Failed to convert string to data")
            return
        }
        
        // Create the Keychain query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing item before adding new one
        SecItemDelete(query as CFDictionary)
        
        // Add the item to the Keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Log.e("Failed to save data to Keychain")
        }
    }
}
