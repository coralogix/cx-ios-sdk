//
//  ErrorInstrumentation.swift
//  
//
//  Created by Coralogix DEV TEAM on 07/04/2024.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    func reportErrorWith(exception: NSException) {
        if let options = self.coralogixExporter?.getOptions(),
           options.shouldInitInstrumentation(instrumentation: .errors) {
            let span = self.getErrorSpan()
            span.setAttribute(key: Keys.domain.rawValue, value: exception.name.rawValue)
            span.setAttribute(key: Keys.code.rawValue, value: 0)
            span.setAttribute(key: Keys.errorMessage.rawValue, value: exception.reason ?? "")
            if let userInfo = exception.userInfo {
                let dict = Helper.convertDictionary(userInfo)
                span.setAttribute(key: Keys.userInfo.rawValue, value: Helper.convertDictionayToJsonString(dict: dict))
            }
            span.end()
        }
    }

    func reportErrorWith(error: NSError) {
        if let options = self.coralogixExporter?.getOptions(),
           options.shouldInitInstrumentation(instrumentation: .errors) {
            let span = self.getErrorSpan()
            span.setAttribute(key: Keys.domain.rawValue, value: error.domain)
            span.setAttribute(key: Keys.code.rawValue, value: error.code)
            span.setAttribute(key: Keys.errorMessage.rawValue, value: error.localizedDescription)
            span.setAttribute(key: Keys.userInfo.rawValue, value: Helper.convertDictionayToJsonString(dict: error.userInfo))
            span.end()
        }
    }
    
    func reportErrorWith(error: Error) {
        if let options = self.coralogixExporter?.getOptions(),
           options.shouldInitInstrumentation(instrumentation: .errors) {
            let span = self.getErrorSpan()
            span.setAttribute(key: Keys.domain.rawValue, value: String(describing: type(of: error)))
            span.setAttribute(key: Keys.code.rawValue, value: 0)
            span.setAttribute(key: Keys.errorMessage.rawValue, value: error.localizedDescription)
            span.end()
        }
    }

    func reportErrorWith(message: String, data: [String: Any]?) {
        if let options = self.coralogixExporter?.getOptions(),
           options.shouldInitInstrumentation(instrumentation: .errors) {
            self.log(severity: CoralogixLogSeverity.error, message: message, data: data)
        }
    }
    
    // Use By Flutter
    func reportErrorWith(message: String, stackTrace: String?) {
        let stackTraceJson = stackTrace.flatMap {
            let stackTraceArray = Helper.parseStackTrace($0)
            return Helper.convertArrayToJsonString(array: stackTraceArray)
        }
        reportErrorInternal(message: message, stackTraceJson: stackTraceJson)
    }
    
    // Use By React Native
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
        if let options = self.coralogixExporter?.getOptions(),
           options.shouldInitInstrumentation(instrumentation: .errors) {
            let span = self.getErrorSpan()
            span.setAttribute(key: Keys.domain.rawValue, value: "")
            span.setAttribute(key: Keys.code.rawValue, value: 0)
            span.setAttribute(key: Keys.errorMessage.rawValue, value: message)
            
            if let errorType = errorType {
                span.setAttribute(key: Keys.errorType.rawValue, value: errorType)
            }
            
            if let stackTraceJson = stackTraceJson {
                span.setAttribute(key: Keys.stackTrace.rawValue, value: stackTraceJson)
            }
            
            span.end()
        }
    }

    func logWith(severity: CoralogixLogSeverity,
                 message: String,
                 data: [String: Any]?) {
        if let options = self.coralogixExporter?.getOptions(),
           options.shouldInitInstrumentation(instrumentation: .custom) ||
            options.shouldInitInstrumentation(instrumentation: .lifeCycle) {
            var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
            span.setAttribute(key: Keys.message.rawValue, value: message)
            span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.log.rawValue)
            span.setAttribute(key: Keys.source.rawValue, value: Keys.code.rawValue)
            span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(severity.rawValue))
            
            if let data = data {
                span.setAttribute(key: Keys.data.rawValue, value: Helper.convertDictionayToJsonString(dict: data))
            }
            
            self.addUserMetadata(to: &span)
            
            if severity.rawValue == CoralogixLogSeverity.error.rawValue {
                self.addScreenshotId(to: &span)
            }
            span.end()
        }
    }
    
    internal func getErrorSpan() -> any Span {
        var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.error.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.error.rawValue))
        self.addUserMetadata(to: &span)
        self.addScreenshotId(to: &span)
        return span
    }
    
    internal func addScreenshotId(to span: inout any Span) {
        if let sessionReplay = SdkManager.shared.getSessionReplay(),
           let coralogixExporter = self.coralogixExporter {
            let screenshotLocation = coralogixExporter.getScreenshotManager().nextScreenshotLocation
            span.setAttribute(key: Keys.screenshotId.rawValue, value: screenshotLocation.screenshotId)
            span.setAttribute(key: Keys.page.rawValue, value: screenshotLocation.page)
            _ = sessionReplay.captureEvent(properties: screenshotLocation.toProperties())
        }
    }
}
