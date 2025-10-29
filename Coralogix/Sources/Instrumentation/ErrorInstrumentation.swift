//
//  ErrorInstrumentation.swift
//  
//
//  Created by Coralogix DEV TEAM on 07/04/2024.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    // MARK: - Feature flags
    private var isErrorsEnabled: Bool {
        self.options?.shouldInitInstrumentation(instrumentation: .errors) ?? false
    }
    
    private var isCustomOrLifecycleEnabled: Bool {
        let opts = self.options
        return (opts?.shouldInitInstrumentation(instrumentation: .custom) ?? false)
        || (opts?.shouldInitInstrumentation(instrumentation: .lifeCycle) ?? false)
    }
    
    func reportErrorWith(exception: NSException) {
        guard isErrorsEnabled else { return }
        let userInfo = Helper.convertDictionary(exception.userInfo ?? [:])
        self.writeError(
            domain: exception.name.rawValue,
            code: 0,
            message: exception.reason ?? "",
            userInfo: userInfo
        )
    }
    
    func reportErrorWith(error: NSError) {
        guard isErrorsEnabled else { return }
        self.writeError(
            domain: error.domain,
            code: error.code,
            message: error.localizedDescription,
            userInfo: error.userInfo
        )
    }
    
    func reportErrorWith(error: Error) {
        guard isErrorsEnabled else { return }
        self.writeError(
            domain: String(describing: type(of: error)),
            code: 0,
            message: error.localizedDescription
        )
    }

    func reportErrorWith(message: String, data: [String: Any]?) {
        guard isErrorsEnabled else { return }
        self.log(severity: CoralogixLogSeverity.error, message: message, data: data)
    }
    
    //MARK: - Used By Flutter
    func reportErrorWith(message: String, stackTrace: String?) {
        let stackTraceJson = stackTrace.flatMap {
            let stackTraceArray = Helper.parseStackTrace($0)
            return Helper.convertArrayToJsonString(array: stackTraceArray)
        }
        reportErrorInternal(message: message, stackTraceJson: stackTraceJson)
    }
    
    //MARK: - Used By React Native
    func reportErrorWith(message: String,
                         stackTrace: [[String: Any]],
                         errorType: String?) {
        let stackTraceJson = Helper.convertArrayToJsonString(array: stackTrace)
        reportErrorInternal(message: message,
                            stackTraceJson: stackTraceJson,
                            errorType: errorType)
    }
    
    private func reportErrorInternal(message: String,
                                     stackTraceJson: String?,
                                     errorType: String? = nil) {
        guard isErrorsEnabled else { return }
        self.writeError(
            domain: "",
            code: 0,
            message: message,
            stackTraceJson: stackTraceJson,
            errorType: errorType
        )
    }

    func logWith(severity: CoralogixLogSeverity,
                 message: String,
                 data: [String: Any]?,
                 labels: [String: Any]?) {
        guard isCustomOrLifecycleEnabled else { return }
        var span = self.makeSpan(event: .log, source: .code, severity: severity)
        span.setAttribute(key: Keys.message.rawValue, value: message)
        
        if let labels = labels {
            span.setAttribute(key: Keys.customLabels.rawValue, value: Helper.convertDictionayToJsonString(dict: labels))
        }
        
        if let data = data {
            span.setAttribute(key: Keys.data.rawValue, value: Helper.convertDictionayToJsonString(dict: data))
        }
                
        if severity == .error { self.recordScreenshotForSpan(to: &span) }
        span.end()
    }
    
    // MARK: - Helpers
    internal func recordScreenshotForSpan(to span: inout any Span) {
        if let sessionReplay = SdkManager.shared.getSessionReplay(),
           let coralogixExporter = self.coralogixExporter {
            let screenshotLocation = coralogixExporter.getScreenshotManager().nextScreenshotLocation
            let result = recordSessionReplayEvent(for: screenshotLocation, via: sessionReplay)
            switch result {
            case .failure(let error):
                if error == .skippingEvent {
                    coralogixExporter.getScreenshotManager().revertScreenshotCounter()
                }
            case .success():
                applyScreenshotAttributes(screenshotLocation, to: &span)
            }
        }
    }
    
    public func applyScreenshotAttributes(_ location: ScreenshotLocation, to span: inout any Span) {
        span.setAttribute(key: Keys.screenshotId.rawValue, value: location.screenshotId)
        span.setAttribute(key: Keys.page.rawValue,         value: location.page)
    }
    
    internal func recordSessionReplayEvent(for location: ScreenshotLocation, via sessionReplay: SessionReplayInterface) -> Result<Void, CaptureEventError> {
        return sessionReplay.captureEvent(properties: location.toProperties())
    }
    
    private func writeError(domain: String, code: Int, message: String,
                            userInfo: [String: Any]? = nil,
                            stackTraceJson: String? = nil,
                            errorType: String? = nil) {
        var span = makeSpan(event: .error, source: .console, severity: .error)
        span.setAttribute(key: Keys.domain.rawValue, value: domain)
        span.setAttribute(key: Keys.code.rawValue, value: code)
        span.setAttribute(key: Keys.errorMessage.rawValue, value: message)
        if let errorType { span.setAttribute(key: Keys.errorType.rawValue, value: errorType) }
        if let stackTraceJson { span.setAttribute(key: Keys.stackTrace.rawValue, value: stackTraceJson) }
        if let userInfo, !userInfo.isEmpty {
            span.setAttribute(key: Keys.userInfo.rawValue, value: Helper.convertDictionayToJsonString(dict: userInfo))
        }
        recordScreenshotForSpan(to: &span)
        span.end()
    }
}
