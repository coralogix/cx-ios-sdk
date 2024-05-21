//
//  NetworkInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 07/04/2024.
//

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import URLSessionInstrumentation

extension CoralogixRum {
    public func initializeSessionInstrumentation() {
        self.sessionInstrumentation = URLSessionInstrumentation(configuration: URLSessionInstrumentationConfiguration(spanCustomization: self.spanCustomization, receivedResponse: self.receivedResponse))
    }
    
    private func spanCustomization(request: URLRequest, spanBuilder: SpanBuilder) {
        spanBuilder.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.networkRequest.rawValue)
        spanBuilder.setAttribute(key: Keys.source.rawValue, value: Keys.fetch.rawValue)
        spanBuilder.setAttribute(key: Keys.timestamp.rawValue, value: Date().timeIntervalSince1970.milliseconds)
    }
    
    private func receivedResponse(response: URLResponse, data: DataOrFile?, span: Span) {
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            let logSeverity = statusCode > 400 ?  CoralogixLogSeverity.error : CoralogixLogSeverity.info
            span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(logSeverity.rawValue))
        }
        span.setAttribute(key: Keys.userId.rawValue, value: self.coralogixExporter.getOptions().userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: self.coralogixExporter.getOptions().userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: self.coralogixExporter.getOptions().userContext?.userEmail ?? "")
        span.setAttribute(key: Keys.environment.rawValue, value: self.coralogixExporter.getOptions().environment)
    }
}
