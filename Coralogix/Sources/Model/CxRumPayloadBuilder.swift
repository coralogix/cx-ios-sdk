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
    // Injectable so tests on iOS can build the tvOS payload.
    var os: String = Global.getOs()

    /// The `tv` platform carries the mobile objects under `tv_*` keys.
    private var isTv: Bool { Self.isTv(os: os) }
    
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
        addSdk(to: &result)
        addVersionMetadata(to: &result)
        addSessionContext(to: &result)
        addEventContext(to: &result)
        addEnvironment(to: &result)
        addTraceAndSpanIds(to: &result)
        addPlatform(to: &result)
        addDeviceContext(to: &result)
        addDeviceState(to: &result)
        addProductAnalyticsFields(to: &result)
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
        addMeasurementContext(to: &result)
    }
    
    private func addViewManagerContext(to result: inout [String: Any]) {
        // Frozen view wins; only non-SDK spans (no frozen view) fall back to the live ViewManager.
        // Native and hybrid (RN/Flutter setView-fed) events both carry a frozen view.
        if let viewName = rum.viewName {
            result[Keys.viewContext.rawValue] = [Keys.view.rawValue: viewName]
            return
        }

        guard let viewManager = self.viewManager else { return }
        if let sessionContext = rum.sessionContext,
           sessionContext.isPidEqualToOldPid == true {
            result[Keys.viewContext.rawValue] = viewManager.getPrevDictionary()
        } else {
            result[Keys.viewContext.rawValue] = viewManager.getDictionary()
        }
    }
    
    private func addLabels(to result: inout [String: Any]) {
        if let labels = rum.labels {
            result[Keys.labels.rawValue] = labels
        }
    }
    

    /// Whether an OS name, as `Global.getOs()` reports it, sends under the `tv` platform.
    static func isTv(os: String) -> Bool {
        return os == Keys.tvos.rawValue
    }

    /// The `platform` wire value for an OS name as `Global.getOs()` reports it.
    static func platform(for os: String) -> String {
        return isTv(os: os) ? Keys.tv.rawValue : Keys.mobile.rawValue
    }

    // MARK: - Basic Detail Helpers

    // Each function below has a single, clear responsibility.
    private func addFingerprint(to result: inout [String: Any]) {
        result[Keys.fingerPrint.rawValue] = rum.fingerPrint
    }

    private func addTimestamp(to result: inout [String: Any]) {
        result[Keys.timestamp.rawValue] = rum.timeStamp.milliseconds
    }

    private func addSdk(to result: inout [String: Any]) {
        let key = isTv ? Keys.tvSdk : Keys.mobileSdk
        result[key.rawValue] = rum.mobileSDK.getDictionary()
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
        result[Keys.platform.rawValue] = Self.platform(for: os)
    }

    // tvOS has no WebKit and no battery, so these would only ever carry placeholders
    // ("undefined", "-1.0") that read as real values; the `tv` schema says to omit them.
    private func addDeviceContext(to result: inout [String: Any]) {
        var deviceContext = rum.deviceContext.getDictionary()
        if isTv { deviceContext[Keys.userAgent.rawValue] = nil }
        result[Keys.deviceContext.rawValue] = deviceContext
    }

    private func addDeviceState(to result: inout [String: Any]) {
        var deviceState = rum.deviceState.getDictionary()
        if isTv { deviceState[Keys.battery.rawValue] = nil }
        result[Keys.deviceState.rawValue] = deviceState
    }

    // CX-44687: product-analytics fields at cx_rum top level.
    // `isNavigationEvent` is always emitted (true/false). `view_number` is omitted
    // entirely on spans fired before any view has appeared so consumers can
    // distinguish "no view yet" from "view #0".
    private func addProductAnalyticsFields(to result: inout [String: Any]) {
        result[Keys.isNavigationEvent.rawValue] = rum.isNavigationEvent
        if let viewNumber = rum.viewNumber {
            result[Keys.viewNumber.rawValue] = viewNumber
        }
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
            let key = isTv ? Keys.tvVitalsContext : Keys.mobileVitalsContext
            result[key.rawValue] = mobileVitalsContext.getMobileVitalsDictionary()
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
        guard rum.eventContext.type == CoralogixEventType.userInteraction,
              let interactionContext = rum.interactionContext else { return }
        let dictionary = interactionContext.getDictionary()
        // The `tv` schema rejects undeclared fields, so tvOS keeps only the ones it declares
        // rather than dropping today's mobile-only extras by name.
        result[Keys.interactionContext.rawValue] = isTv
            ? dictionary.filter { Self.tvInteractionKeys.contains($0.key) }
            : dictionary
    }

    private static let tvInteractionKeys: Set<String> = [
        Keys.eventName.rawValue, Keys.targetElement.rawValue, Keys.elementId.rawValue,
        Keys.targetElementInnerText.rawValue, Keys.attributes.rawValue
    ]
    
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
    
    private func addMeasurementContext(to result: inout [String: Any]) {
        if let measurementContext = rum.measurementContext, measurementContext.isValid()  {
            result[Keys.customMeasurementContext.rawValue] = measurementContext.getDictionary()
        }
    }
}
