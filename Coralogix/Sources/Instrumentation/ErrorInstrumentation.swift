//
//  ErrorInstrumentation.swift
//  
//
//  Created by Coralogix DEV TEAM on 07/04/2024.
//

import Foundation

extension CoralogixRum {
    
    internal func tracer() -> Tracer {
        return OpenTelemetry.instance.tracerProvider.get(instrumentationName: Keys.iosSdk.rawValue,
                                                         instrumentationVersion: Global.sdk.rawValue)
    }
    
    func reportErrorWith(exception: NSException) {
        if self.options.shouldInitInstumentation(instumentation: .errors) {
            let span = self.getSpan()
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
        if self.options.shouldInitInstumentation(instumentation: .errors) {
            let span = self.getSpan()
            span.setAttribute(key: Keys.domain.rawValue, value: error.domain)
            span.setAttribute(key: Keys.code.rawValue, value: error.code)
            span.setAttribute(key: Keys.errorMessage.rawValue, value: error.localizedDescription)
            span.setAttribute(key: Keys.userInfo.rawValue, value: Helper.convertDictionayToJsonString(dict: error.userInfo))
            span.end()
        }
    }
    
    func reportErrorWith(error: Error) {
        if self.options.shouldInitInstumentation(instumentation: .errors) {
            let span = self.getSpan()
            span.setAttribute(key: Keys.domain.rawValue, value: String(describing: type(of: error)))
            span.setAttribute(key: Keys.code.rawValue, value: 0)
            span.setAttribute(key: Keys.errorMessage.rawValue, value: error.localizedDescription)
            span.end()
        }
    }

    func reportErrorWith(message: String, data: [String: Any]?) {
        if self.options.shouldInitInstumentation(instumentation: .errors) {
            self.log(severity: CoralogixLogSeverity.error, message: message, data: data)
        }
    }
    
    func reportErrorWith(message: String, stackTrace: String?) {
        let stackTraceJson = stackTrace.flatMap {
            let stackTraceArray = Helper.parseStackTrace($0)
            return Helper.convertArrayToJsonString(array: stackTraceArray)
        }
        reportErrorInternal(message: message, stackTraceJson: stackTraceJson)
    }
    
    func reportErrorWith(message: String, stackTrace: [[String: Any]]) {
        let stackTraceJson = Helper.convertArrayToJsonString(array: stackTrace)
        reportErrorInternal(message: message, stackTraceJson: stackTraceJson)
    }
    
    private func reportErrorInternal(message: String, stackTraceJson: String?) {
        if self.options.shouldInitInstumentation(instumentation: .errors) {
            let span = self.getSpan()
            span.setAttribute(key: Keys.domain.rawValue, value: "")
            span.setAttribute(key: Keys.code.rawValue, value: 0)
            span.setAttribute(key: Keys.errorMessage.rawValue, value: message)
            
            if let stackTraceJson = stackTraceJson {
                span.setAttribute(key: Keys.stackTrace.rawValue, value: stackTraceJson)
            }
            
            span.end()
        }
    }

    func logWith(severity: CoralogixLogSeverity,
                 message: String,
                 data: [String: Any]?) {
        if self.options.shouldInitInstumentation(instumentation: .custom) ||
            self.options.shouldInitInstumentation(instumentation: .lifeCycle) {
            var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
            span.setAttribute(key: Keys.message.rawValue, value: message)
            span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.log.rawValue)
            span.setAttribute(key: Keys.source.rawValue, value: Keys.code.rawValue)
            span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(severity.rawValue))
            
            if let data = data {
                span.setAttribute(key: Keys.data.rawValue, value: Helper.convertDictionayToJsonString(dict: data))
            }
            
            self.addUserMetadata(to: &span)
            
            if severity.rawValue == CoralogixLogSeverity.error.rawValue {
                self.addSnapshotContext(to: &span)
            }
            span.end()
        }
    }
    
    private func getSpan() -> Span {
        var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.error.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.error.rawValue))
        self.addUserMetadata(to: &span)
        self.addSnapshotContext(to: &span)
        return span
    }
    
    private func addSnapshotContext(to span: inout Span) {
        self.sessionManager.incrementErrorCounter()
        let snapshot = SnapshotConext(timestemp: Date().timeIntervalSince1970,
                                      errorCount: self.sessionManager.getErrorCount(),
                                      viewCount: self.viewManager.getUniqueViewCount(),
                                      clickCount: self.sessionManager.getClickCount())
        let dict = Helper.convertDictionary(snapshot.getDictionary())
        span.setAttribute(key: Keys.snapshotContext.rawValue,
                          value: Helper.convertDictionayToJsonString(dict: dict))
    }
}
