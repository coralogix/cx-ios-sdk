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

    func reportErrorWith(error: NSError) {
        let span = self.getSpan()
        span.setAttribute(key: Keys.domain.rawValue, value: error.domain)
        span.setAttribute(key: Keys.code.rawValue, value: error.code)
        span.setAttribute(key: Keys.errorMessage.rawValue, value: error.localizedDescription)
        span.setAttribute(key: Keys.userInfo.rawValue, value: Helper.convertDictionayToJsonString(dict: error.userInfo))
        span.end()
    }
    
    func reportErrorWith(error: Error) {
        let span = self.getSpan()
        span.setAttribute(key: Keys.domain.rawValue, value: String(describing: type(of: error)))
        span.setAttribute(key: Keys.code.rawValue, value: 0)
        span.setAttribute(key: Keys.errorMessage.rawValue, value: error.localizedDescription)
        span.end()
    }

    func reportErrorWith(message: String, data: [String: Any]?) {
        self.log(severity: CoralogixLogSeverity.error, message: message, data: data)
    }
    
    func reportErrorWith(message: String, stackTrace: String?) {
        let span = self.getSpan()
        span.setAttribute(key: Keys.domain.rawValue, value: "")
        span.setAttribute(key: Keys.code.rawValue, value: 0)
        span.setAttribute(key: Keys.errorMessage.rawValue, value: message)
        
        if let stackTrace = stackTrace {
            let stackTraceArray = Helper.parseStackTrace(stackTrace)
            span.setAttribute(key: Keys.stackTrace.rawValue, value: Helper.convertArrayToJsonString(array: stackTraceArray))
        }
        span.end()
    }
    
    func logWith(severity: CoralogixLogSeverity,
                 message: String,
                 data: [String: Any]?) {
        var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        span.setAttribute(key: Keys.message.rawValue, value: message)
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.log.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.code.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(severity.rawValue))

        if let data = data {
            span.setAttribute(key: Keys.data.rawValue, value: Helper.convertDictionayToJsonString(dict: data))
        }
        
        span.setAttribute(key: Keys.userId.rawValue, value: self.coralogixExporter.getOptions().userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: self.coralogixExporter.getOptions().userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: self.coralogixExporter.getOptions().userContext?.userEmail ?? "" )
        span.setAttribute(key: Keys.environment.rawValue, value: self.coralogixExporter.getOptions().environment)
        
        if severity.rawValue == CoralogixLogSeverity.error.rawValue {
            self.addSnapshotContext(to: &span)
        }
        span.end()
    }
    
    private func getSpan() -> Span {
        var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.error.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.error.rawValue))
        
        span.setAttribute(key: Keys.userId.rawValue, value: self.coralogixExporter.getOptions().userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: self.coralogixExporter.getOptions().userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: self.coralogixExporter.getOptions().userContext?.userEmail ?? "")
        span.setAttribute(key: Keys.environment.rawValue, value: self.coralogixExporter.getOptions().environment)
        
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
