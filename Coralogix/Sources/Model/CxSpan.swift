//
//  CxSpan.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation

public class CxSpan {
    let versionMetadata: VersionMetadata
    let applicationName: String
    let subsystemName: String
    let isErrorWithStacktrace: Bool = false
    var severity: Int = 0
    var timeStamp: TimeInterval = 0
    var cxRum: CxRum
    var instrumentationData: InstrumentationData?
    var beforeSend: (([String: Any]) -> [String: Any]?)?
    
    init(otel: SpanDataProtocol,
         versionMetadata: VersionMetadata,
         sessionManager: SessionManager,
         networkManager: NetworkProtocol,
         viewManager: ViewManager,
         metricsManager: MetricsManager,
         userMetadata: [String: String]?,
         beforeSend: (([String: Any]) -> [String: Any]?)?,
         labels: [String: Any]?) {
        self.applicationName = versionMetadata.appName
        self.versionMetadata = versionMetadata
        self.subsystemName = Keys.cxRum.rawValue
        self.beforeSend = beforeSend
        if let severity = otel.getAttribute(forKey: Keys.severity.rawValue) as? String {
            self.severity = Int(severity) ?? 0
        }
        self.timeStamp = otel.getStartTime() ?? Date().timeIntervalSince1970
        self.cxRum = CxRum(otel: otel,
                           versionMetadata: versionMetadata,
                           sessionManager: sessionManager,
                           viewManager: viewManager,
                           networkManager: networkManager,
                           metricsManager: metricsManager,
                           userMetadata: userMetadata,
                           labels: labels)
        
        if cxRum.eventContext.type == CoralogixEventType.networkRequest {
            self.instrumentationData = InstrumentationData(otel: otel, labels: labels)
        }
    }
    
    func getDictionary() -> [String: Any]? {
        var result = [String: Any]()
        // Populate the basic metadata
        self.populateBasicMetadata(in: &result)
        
        let originalCxRum = self.cxRum.getDictionary()
        if beforeSend != nil {
            let subsetOfCxRum = self.createSubsetOfCxRum(from: originalCxRum)
            if let editableCxRum = self.beforeSend?(subsetOfCxRum) {
                let mergedDict = mergeDictionaries(original: originalCxRum, editable: editableCxRum)
                result[Keys.text.rawValue] = [Keys.cxRum.rawValue: mergedDict]
            } else {
                return nil // editableCxRum is nil we need to drop that span
            }
        } else {
            result[Keys.text.rawValue] = [Keys.cxRum.rawValue: originalCxRum]
        }
        
        // Add instrumentation data if applicable
        self.addInstrumentationData(to: &result)
        return result
    }
    
    private func populateBasicMetadata(in result: inout [String: Any]) {
        result[Keys.versionMetaData.rawValue] = versionMetadata.getDictionary()
        result[Keys.applicationName.rawValue] = self.applicationName
        result[Keys.subsystemName.rawValue] = self.subsystemName
        result[Keys.severity.rawValue] = self.severity
        result[Keys.timestamp.rawValue] = self.timeStamp.milliseconds
    }
    
    private func addInstrumentationData(to result: inout [String: Any]) {
        if cxRum.eventContext.type == CoralogixEventType.networkRequest,
           let instrumentationData = self.instrumentationData?.getDictionary() {
            result[Keys.instrumentationData.rawValue] = instrumentationData
        }
    }
    
    func mergeDictionaries(original: [String: Any], editable: [String: Any]) -> [String: Any] {
        var mergedDict = original

        for (key, value) in editable {
            if let existingValue = mergedDict[key] {
                // If both values are dictionaries, merge them recursively
                if let existingDict = existingValue as? [String: Any], let newDict = value as? [String: Any] {
                    mergedDict[key] = mergeDictionaries(original: existingDict, editable: newDict)
                } else {
                    // If the key already exists and is not a dictionary, overwrite with the new value
                    mergedDict[key] = value
                }
            } else {
                // If the key does not exist in dict1, add the new key-value pair
                mergedDict[key] = value
            }
        }

        return mergedDict
    }
    
    func createSubsetOfCxRum(from originalCxRum: [String: Any]) -> [String: Any] {
        var editableCxRum = originalCxRum
        // Remove sessionCreationDate and sessionId form sessionContext
        if var sessionContext = editableCxRum[Keys.sessionContext.rawValue] as? [String: Any] {
            sessionContext.removeValue(forKey: Keys.sessionCreationDate.rawValue)
            sessionContext.removeValue(forKey: Keys.sessionId.rawValue)
            editableCxRum[Keys.sessionContext.rawValue] = sessionContext
        }
        
        editableCxRum.removeValue(forKey: Keys.snapshotContext.rawValue)
        editableCxRum.removeValue(forKey: Keys.mobileSdk.rawValue)
        editableCxRum.removeValue(forKey: Keys.timestamp.rawValue)
       
        return editableCxRum
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
