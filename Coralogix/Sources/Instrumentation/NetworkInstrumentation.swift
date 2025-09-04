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
        guard let options = self.options else {
            Log.e("[Coralogix] missing coralogix options")
            return
        }
        
        if options.enableSwizzling == true {
            self.readinessGroup.enter()
            
            if Thread.isMainThread {
                // Run immediately, avoid async race
                let group = readinessGroup
                defer { group.leave() }
                self.initializeInstrumentation(options: options)
                self.isNetworkInstrumentationReady = true
            } else {
                // Schedule on main, wait until done
                let group = readinessGroup
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.initializeInstrumentation(options: options)
                    self.isNetworkInstrumentationReady = true
                    group.leave()
                }
                
                // 🚦 Block background thread briefly to ensure swizzling is ready
                let start = Date()
                let result = readinessGroup.wait(timeout: .now() + 0.5)
                let elapsed = Date().timeIntervalSince(start)
                
                if result == .timedOut {
                    Log.w("[Coralogix] initializeNetworkInstrumentation() timed out after \(elapsed)s. Swizzling may be incomplete!")
                } else if elapsed > 0 {
                    Log.d("[Coralogix] initializeNetworkInstrumentation() waited \(elapsed)s for network swizzling.")
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
            options = self.options
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
        span.setAttribute(key: Keys.customSpanId.rawValue, value: dictionary[Keys.customSpanId.rawValue] as? String ?? "")
        span.setAttribute(key: Keys.customTraceId.rawValue, value: dictionary[Keys.customTraceId.rawValue] as? String ?? "")
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
