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
    var severity: Int
    var cxRum: CxRum
    var instrumentationData: InstrumentationData?
    var beforeSend: (([String: Any]) -> [String: Any]?)?
    let viewManager: ViewManager?
    weak var sessionManager: SessionManager?
    
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
        self.sessionManager = sessionManager

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
        self.severity = cxRum.eventContext.severity
        
        // `instrumentation_data.otelSpan` enables Tracing ingestion (Browser: traces-exporter + markSpanAsOtelToSend).
        if cxRum.eventContext.type == .networkRequest || cxRum.eventContext.type == .customSpan {
            self.instrumentationData = InstrumentationData(otel: otel, cxRum: cxRum, viewManager: viewManager)
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
                var mergedDict = mergeDictionaries(original: originalCxRum, editable: editableCxRum)

                // snapshotContext is stripped from the editable subset before beforeSend is called,
                // but a callback could still inject it into the returned dict, causing mergeDictionaries
                // to deep-merge corrupted counts into our internal value.
                // Always restore from originalCxRum so errorCount/viewCount cannot be tampered with.
                // Assigning nil removes the key when the original had no snapshot (no-snapshot spans).
                mergedDict[Keys.snapshotContext.rawValue] = originalCxRum[Keys.snapshotContext.rawValue]

                // Sync severity from editableCxRum to both the top-level field and
                // mergedDict[eventContext][severity] so they remain consistent.
                // parseSeverity accepts Int or numeric String (matching the OTEL init path)
                // and falls back to the original value so a missing/unparseable severity
                // is treated as "no change" rather than silently skipping reconciliation.
                //
                // Priority: eventContext[severity] → top-level editableCxRum[severity] → original.
                // This covers the case where beforeSend removes eventContext entirely but
                // still sets a top-level severity key.
                let editableEventContext = editableCxRum[Keys.eventContext.rawValue] as? [String: Any]
                let severitySource = editableEventContext?[Keys.severity.rawValue]
                    ?? editableCxRum[Keys.severity.rawValue]
                let newSeverity = CxSpan.parseSeverity(severitySource, fallback: self.cxRum.eventContext.severity)

                // Only write when the value actually changed to avoid a no-op overwrite
                // (e.g. when beforeSend returns an eventContext without a severity key,
                // parseSeverity returns the original value via fallback).
                if newSeverity != self.cxRum.eventContext.severity {
                    result[Keys.severity.rawValue] = newSeverity
                }

                // Write the normalised Int back into mergedDict so that
                // text.cxRum.eventContext.severity matches the top-level severity.
                if var ecDict = mergedDict[Keys.eventContext.rawValue] as? [String: Any] {
                    ecDict[Keys.severity.rawValue] = newSeverity
                    mergedDict[Keys.eventContext.rawValue] = ecDict
                }

                // Assign mergedDict before updateSnapshotErrorCount, which re-assigns
                // result[Keys.text.rawValue] to patch snapshotContext.errorCount in place.
                result[Keys.text.rawValue] = [Keys.cxRum.rawValue: mergedDict]

                // BUGV2-5379: adjust errorCount when beforeSend changes severity across the Error boundary.
                // Runs unconditionally so the counter stays correct even when beforeSend removes
                // eventContext and expresses the severity change at the top level instead.
                // Capture sessionManager once so the counter mutation and the getErrorCount()
                // read inside updateSnapshotErrorCount see the same object (closes the TOCTOU
                // window that the weak var would otherwise leave open).
                let errorSeverity = CoralogixLogSeverity.error.rawValue
                let wasError = self.cxRum.eventContext.severity == errorSeverity
                let isNowError = newSeverity == errorSeverity
                if wasError != isNowError, let sm = sessionManager {
                    if wasError {
                        sm.decrementErrorCounter()
                    } else {
                        sm.incrementErrorCounter()
                    }
                    updateSnapshotErrorCount(in: &result, sessionManager: sm)
                }
            } else {
                // BUGV2-5379: span dropped by beforeSend — undo error increment if it was an Error
                if self.cxRum.eventContext.severity == CoralogixLogSeverity.error.rawValue {
                    sessionManager?.decrementErrorCounter()
                }
                return nil
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
        if cxRum.eventContext.type == .networkRequest || cxRum.eventContext.type == .customSpan,
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
    
    /// Valid severity range (CoralogixLogSeverity: debug=1 through critical=6).
    private static let validSeverityRange = 1...6

    /// Normalizes a severity value supplied by beforeSend into an Int.
    /// Accepts Int directly or a numeric String (matching the OTEL attribute initializer path).
    /// Returns `fallback` when the value is nil, non-numeric, out of valid range (1-6), or an unrecognised type.
    private static func parseSeverity(_ value: Any?, fallback: Int) -> Int {
        let parsed = (value as? Int) ?? (value as? String).flatMap(Int.init)
        return parsed.flatMap { validSeverityRange.contains($0) ? $0 : nil } ?? fallback
    }

    private func updateSnapshotErrorCount(in result: inout [String: Any], sessionManager: SessionManager) {
        guard var textDict = result[Keys.text.rawValue] as? [String: Any],
              var cxRumDict = textDict[Keys.cxRum.rawValue] as? [String: Any] else {
            return
        }
        // Fall back to an empty dict if snapshotContext is absent, NSNull, or a non-dict type,
        // so errorCount is always written after beforeSend runs.
        var snapshotDict = (cxRumDict[Keys.snapshotContext.rawValue] as? [String: Any]) ?? [:]
        snapshotDict[Keys.errorCount.rawValue] = sessionManager.getErrorCount()
        cxRumDict[Keys.snapshotContext.rawValue] = snapshotDict
        textDict[Keys.cxRum.rawValue] = cxRumDict
        result[Keys.text.rawValue] = textDict
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
