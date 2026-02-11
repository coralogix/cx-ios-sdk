//
//  CxSpan.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import CoralogixInternal

public class CxSpan {
    let versionMetadata: VersionMetadata
    let applicationName: String
    let subsystemName: String
    let isErrorWithStacktrace: Bool = false
    var severity: Int = 0
    var cxRum: CxRum
    var instrumentationData: InstrumentationData?
    var beforeSend: (([String: Any]) -> [String: Any]?)?
    let viewManager: ViewManager?
    
    init?(otel: SpanDataProtocol,
          versionMetadata: VersionMetadata,
          sessionManager: SessionManager,
          networkManager: NetworkProtocol,
          viewManager: ViewManager,
          metricsManager: MetricsManager,
          options: CoralogixExporterOptions) {
        
        self.viewManager = viewManager
        self.applicationName = versionMetadata.appName
        self.versionMetadata = versionMetadata
        self.subsystemName = Keys.cxRum.rawValue
        self.beforeSend = options.beforeSend
        if let severity = otel.getAttribute(forKey: Keys.severity.rawValue) as? String {
            self.severity = Int(severity) ?? 0
        }

        let rumBuilder = CxRumBuilder(otel: otel,
                                      versionMetadata: versionMetadata,
                                      sessionManager: sessionManager,
                                      viewManager: viewManager,
                                      networkManager: networkManager,
                                      options: options)
        // 2. Build the immutable data object.
        // If build() returns nil (missing session attributes), fail initialization
        guard let cxRum = rumBuilder.build() else {
            return nil
        }
        self.cxRum = cxRum
        
        if cxRum.eventContext.type == CoralogixEventType.networkRequest {
            self.instrumentationData = InstrumentationData(otel: otel, labels: options.labels)
        }
    }
    
    func getDictionary() -> [String: Any]? {
        var result = [String: Any]()
        // Populate the basic metadata
        self.populateBasicMetadata(in: &result)
        
        var payloadBuilder = CxRumPayloadBuilder(rum: self.cxRum, viewManager: self.viewManager)
        let originalCxRum = payloadBuilder.build()
        if beforeSend != nil {
            let subsetOfCxRum = self.createSubsetOfCxRum(from: originalCxRum)
            if let editableCxRum = self.beforeSend?(subsetOfCxRum) {
                let mergedDict = mergeDictionaries(original: originalCxRum, editable: editableCxRum)
                result[Keys.text.rawValue] = [Keys.cxRum.rawValue: mergedDict]
                
                // Sync severity from editableCxRum to CxSpan's top-level severity
                if let eventContext = editableCxRum[Keys.eventContext.rawValue] as? [String: Any],
                   let newSeverity = eventContext[Keys.severity.rawValue] as? Int {
                    result[Keys.severity.rawValue] = newSeverity
                }
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
        result[Keys.timestamp.rawValue] = self.cxRum.timeStamp.milliseconds
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

protocol KeyChainProtocol: AnyObject {
    func readStringFromKeychain(service: String, key: String) -> String?
    func writeStringToKeychain(service: String, key: String, value: String)
}

public struct SessionMetadata {
    var sessionId: String
    var sessionCreationDate: TimeInterval
    var oldPid: String?
    var oldSessionId: String?
    var oldSessionTimeInterval: TimeInterval?
    
    init(sessionId: String, sessionCreationDate: TimeInterval, using keychain: KeyChainProtocol) {
        self.sessionId = sessionId
        self.sessionCreationDate = sessionCreationDate
        self.loadPrevSession(keychain: keychain)
    }
    
    mutating func resetSessionMetadata() {
        self.sessionId = ""
        self.sessionCreationDate = 0
    }
    
    mutating func loadPrevSession(keychain: KeyChainProtocol) {
        let newPid = getpid()
        
        if let oldPid = keychain.readStringFromKeychain(service: Keys.service.rawValue, key: Keys.pid.rawValue),
           let oldSessionId = keychain.readStringFromKeychain(service: Keys.service.rawValue,
                                                               key: Keys.keySessionId.rawValue),
           let oldSessionTimeInterval = keychain.readStringFromKeychain(service: Keys.service.rawValue,
                                                                         key: Keys.keySessionTimeInterval.rawValue) {
            self.oldPid = oldPid
            self.oldSessionId = oldSessionId
            self.oldSessionTimeInterval = TimeInterval(oldSessionTimeInterval)
        }
        
        keychain.writeStringToKeychain(service: Keys.service.rawValue,
                                        key: Keys.pid.rawValue,
                                        value: String(newPid))
        keychain.writeStringToKeychain(service: Keys.service.rawValue,
                                        key: Keys.keySessionId.rawValue,
                                        value: sessionId)
        keychain.writeStringToKeychain(service: Keys.service.rawValue,
                                        key: Keys.keySessionTimeInterval.rawValue,
                                        value: String(sessionCreationDate))
    }
}
