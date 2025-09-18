//
//  CxRumPayloadBuilder.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 10/09/2025.
//

import Foundation

struct CxRumPayloadBuilder {
    // MARK: - Properties
    
    let rum: CxRum
    // Dependencies needed only for serialization
    let viewManager: ViewManager?
    
    // MARK: - Public Methods
    
    mutating func build() -> [String: Any] {
        var result = [String: Any]()
        
        // The coordinator methods are now called here
        addBasicDetails(to: &result)
        addConditionalContexts(to: &result)
        addViewManagerContext(to: &result)
        addLabels(to: &result)
        
        return result
    }
    
    private func addBasicDetails(to result: inout [String: Any]) {
        addFingerprint(to: &result)
        addTimestamp(to: &result)
        addMobileSdk(to: &result)
        addVersionMetadata(to: &result)
        addSessionContext(to: &result)
        addEventContext(to: &result)
        addEnvironment(to: &result)
        addTraceAndSpanIds(to: &result)
        addPlatform(to: &result)
        addDeviceContext(to: &result)
        addDeviceState(to: &result)
    }
    
    private mutating func addConditionalContexts(to result: inout [String: Any]) {
        addErrorContext(to: &result)
        addNetworkRequestContext(to: &result)
        addMobileVitalsContext(to: &result)
        addLifeCycleContext(to: &result)
        addLogContext(to: &result)
        addInteractionContext(to: &result)
        addInternalContext(to: &result)
        addScreenshotContext(to: &result)
        addPrevSession(to: &result)
        addSnapshotContext(to: &result)
    }
    
    private func addViewManagerContext(to result: inout [String: Any]) {
        if let viewManager = self.viewManager {
            if let sessionContext = rum.sessionContext,
               sessionContext.isPidEqualToOldPid == true {
                result[Keys.viewContext.rawValue] = viewManager.getPrevDictionary()
            } else {
                result[Keys.viewContext.rawValue] = viewManager.getDictionary()
            }
        }
    }
    
    private func addLabels(to result: inout [String: Any]) {
        if let labels = rum.labels {
            result[Keys.labels.rawValue] = labels
        }
    }
    
    // MARK: - Basic Detail Helpers

    // Each function below has a single, clear responsibility.
    private func addFingerprint(to result: inout [String: Any]) {
        result[Keys.fingerPrint.rawValue] = rum.fingerPrint
    }

    private func addTimestamp(to result: inout [String: Any]) {
        result[Keys.timestamp.rawValue] = rum.timeStamp.milliseconds
    }

    private func addMobileSdk(to result: inout [String: Any]) {
        result[Keys.mobileSdk.rawValue] = rum.mobileSDK.getDictionary()
    }

    private func addVersionMetadata(to result: inout [String: Any]) {
        result[Keys.versionMetaData.rawValue] = rum.versionMetadata.getDictionary()
    }

    private func addSessionContext(to result: inout [String: Any]) {
        result[Keys.sessionContext.rawValue] = rum.sessionContext?.getDictionary()
    }

    private func addEventContext(to result: inout [String: Any]) {
        result[Keys.eventContext.rawValue] = rum.eventContext.getDictionary()
    }

    private func addEnvironment(to result: inout [String: Any]) {
        result[Keys.environment.rawValue] = rum.environment
    }

    private func addTraceAndSpanIds(to result: inout [String: Any]) {
        result[Keys.traceId.rawValue] = rum.traceId
        result[Keys.spanId.rawValue] = rum.spanId
    }

    private func addPlatform(to result: inout [String: Any]) {
        let platform = (Global.getOs() == Keys.tvos.rawValue) ? Keys.television.rawValue : Keys.mobile.rawValue
        result[Keys.platform.rawValue] = platform
    }

    private func addDeviceContext(to result: inout [String: Any]) {
        result[Keys.deviceContext.rawValue] = rum.deviceContext.getDictionary()
    }

    private func addDeviceState(to result: inout [String: Any]) {
        result[Keys.deviceState.rawValue] = rum.deviceState.getDictionary()
    }
    
    private func addErrorContext(to result: inout [String: Any]) {
        if rum.eventContext.type == .error {
            result[Keys.errorContext.rawValue] = rum.errorContext.getDictionary()
        }
    }
    
    private func addNetworkRequestContext(to result: inout [String: Any]) {
        if rum.eventContext.type == .networkRequest {
            result[Keys.networkRequestContext.rawValue] = rum.networkRequestContext.getDictionary()
        }
    }
    
    private func addMobileVitalsContext(to result: inout [String: Any]) {
        if rum.eventContext.type == .mobileVitals, let mobileVitalsContext = rum.mobileVitalsContext {
            result[Keys.mobileVitalsContext.rawValue] = mobileVitalsContext.getMobileVitalsDictionary()
        }
    }
    
    private func addLifeCycleContext(to result: inout [String: Any]) {
        if rum.eventContext.type == .lifeCycle {
            result[Keys.lifeCycleContext.rawValue] = rum.lifeCycleContext?.getLifeCycleDictionary()
        }
    }
    
    private func addLogContext(to result: inout [String: Any]) {
        if rum.eventContext.type == .log {
            result[Keys.logContext.rawValue] = rum.logContext.getDictionary()
        }
    }
    
    private func addInteractionContext(to result: inout [String: Any]) {
        if rum.eventContext.type == CoralogixEventType.userInteraction,
           let interactionContext = rum.interactionContext {
            result[Keys.interactionContext.rawValue] = interactionContext.getDictionary()
        }
    }
    
    private func addInternalContext(to result: inout [String: Any]) {
        if rum.eventContext.type == CoralogixEventType.internalKey,
           let internalContext = rum.internalContext {
            result[Keys.internalContext.rawValue] = internalContext.getDictionary()
        }
    }
        
    private func addScreenshotContext(to result: inout [String: Any]) {
        if let screenShotContext = rum.screenShotContext, screenShotContext.isValid() {
            result[Keys.screenshotContext.rawValue] = screenShotContext.getDictionary()
        }
    }
    
    private func addPrevSession(to result: inout [String: Any]) {
        if let prevSessionContext = rum.prevSessionContext {
            result[Keys.prevSession.rawValue] = prevSessionContext.getPrevSessionDictionary()
        }
    }
    
    private mutating func addSnapshotContext(to result: inout [String: Any]) {
        if let snapshotContext = rum.snapshotContext {
            result[Keys.isSnapshotEvent.rawValue] = true
            result[Keys.snapshotContext.rawValue] = snapshotContext.getDictionary()
        }
    }
}
