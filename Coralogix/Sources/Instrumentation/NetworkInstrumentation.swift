//
//  NetworkInstrumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 07/04/2024.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    private static let exporterQueue = DispatchQueue(label: Keys.queueExporter.rawValue)

    public func initializeNetworkInstrumentation() {
        guard let options = self.coralogixExporter?.getOptions() else {
            Log.e("[Coralogix] missing coralogix options")
            return
        }
        
        if options.enableSwizzling == true {
            if Thread.isMainThread {
                self.initializeInstrumentation(options: options)
            } else {
                DispatchQueue.main.async {
                    self.initializeInstrumentation(options: options)
                }
            }
        } else {
            Log.e("[Coralogix] Swizzling is disabled")
        }
    }
    
    internal func initializeInstrumentation(options: CoralogixExporterOptions) {
        let configuration = URLSessionInstrumentationConfiguration(
            spanCustomization: self.spanCustomization,
            shouldInjectTracingHeaders: { [weak self] request in
                return self?.shouldAddTraceParent(to: request, options: options) ?? false
            },
            receivedResponse: self.receivedResponse,
            ignoredClassPrefixes: options.ignoredClassPrefixes
        )
        self.sessionInstrumentation = URLSessionInstrumentation(configuration: configuration)
    }
    
    internal func shouldAddTraceParent(to request: URLRequest, options: CoralogixExporterOptions) -> Bool {
        guard let requestURLString = request.url?.absoluteString else {
            return false
        }
        
        if requestURLString.contains(options.coralogixDomain.rawValue) {
            return false
        }
        
        guard let traceParentDict = options.traceParentInHeader else {
            return false
        }
        
        let traceParent = TraceParentInHeader(params: traceParentDict)
        
        guard traceParent.enable else {
            return false
        }
        
        if let allowedUrls = traceParent.allowedTracingUrls, !allowedUrls.isEmpty {
            if allowedUrls.contains(requestURLString) {
                return true
            }
            
            return Global.isURLMatchesRegexPattern(string: requestURLString, regexs: allowedUrls)
        }
        
        return true
    }
    
    private func spanCustomization(request: URLRequest, spanBuilder: SpanBuilder) {
        spanBuilder.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.networkRequest.rawValue)
        spanBuilder.setAttribute(key: Keys.source.rawValue, value: Keys.fetch.rawValue)
    }
    
    private func receivedResponse(response: URLResponse, data: DataOrFile?, span: any Span) {
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            let logSeverity = statusCode > 400 ?  CoralogixLogSeverity.error : CoralogixLogSeverity.info
            span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(logSeverity.rawValue))
        }
        
        var options: CoralogixExporterOptions?
        CoralogixRum.exporterQueue.sync {
            options = self.coralogixExporter?.getOptions()
        }
        
        guard let options else {
#if DEBUG
            assertionFailure("CoralogixExporterOptions unexpectedly nil during network response handling") // 🆕
#endif
            return
        }
        
        let userContext = options.userContext

        span.setAttribute(key: Keys.userId.rawValue, value: userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: userContext?.userEmail ?? "")
        span.setAttribute(key: Keys.environment.rawValue, value: options.environment)
    }
    
    public func setNetworkRequestContext(dictionary: [String: Any]) {
        let span = self.getSpan()
        
        if let statusCode = dictionary[Keys.statusCode.rawValue] as? Int {
            let logSeverity = statusCode > 400 ?  CoralogixLogSeverity.error : CoralogixLogSeverity.info
            span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(logSeverity.rawValue))
        }
        
        span.setAttribute(key: SemanticAttributes.httpUrl.rawValue, value: dictionary[Keys.url.rawValue] as? String ?? "")
        span.setAttribute(key: SemanticAttributes.netPeerName.rawValue, value: dictionary[Keys.host.rawValue] as? String ?? "")
        span.setAttribute(key: SemanticAttributes.httpMethod.rawValue, value: dictionary[Keys.method.rawValue] as? String ?? "")
        span.setAttribute(key: SemanticAttributes.httpStatusCode.rawValue, value: dictionary[Keys.statusCode.rawValue] as? Int ?? 0)
        span.setAttribute(key: SemanticAttributes.httpResponseBodySize.rawValue, value: dictionary[Keys.httpResponseBodySize.rawValue] as? Int ?? 0)
        span.setAttribute(key: SemanticAttributes.httpTarget.rawValue, value: dictionary[Keys.fragments.rawValue] as? String ?? "")
        span.setAttribute(key: SemanticAttributes.httpScheme.rawValue, value: dictionary[Keys.schema.rawValue] as? String ?? "")
        span.setAttribute(key: Keys.customSpanId.rawValue, value: dictionary[Keys.spanId.rawValue] as? String ?? "")
        span.setAttribute(key: Keys.customTraceId.rawValue, value: dictionary[Keys.traceId.rawValue] as? String ?? "")
        span.end()
    }
    
    private func getSpan() -> any Span {
        var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        self.addUserMetadata(to: &span)
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.networkRequest.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.fetch.rawValue)
        return span
    }
}
