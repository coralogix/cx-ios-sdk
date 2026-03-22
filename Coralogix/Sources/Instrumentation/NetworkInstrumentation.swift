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
            shouldCollectResponsePayload: { request in
                Self.shouldCollectResponsePayload(for: request, options: options)
            },
            shouldCollectRequestPayload: { request in
                Self.shouldCollectRequestPayload(for: request, options: options)
            },
            receivedResponse: self.receivedResponse,
            delegateClassesToInstrument: Self.urlSessionDelegateClassesForReactNative()
        )
        self.sessionInstrumentation = URLSessionInstrumentation(configuration: configuration)
    }
    
    /// React Native uses `RCTHTTPRequestHandler` as its `NSURLSessionDataDelegate` and does not use the
    /// completion-handler API, so response body is only available if this delegate class is instrumented.
    /// Returns the class in an array when present at runtime (safe no-op in non–React Native apps).
    /// - Note: Class name is fixed; if React Native renames this class in a future version, this integration will no-op until updated.
    private static func urlSessionDelegateClassesForReactNative() -> [AnyClass]? {
        guard let cls = NSClassFromString("RCTHTTPRequestHandler") else { return nil }
        return [cls]
    }

    /// Returns whether response body should be buffered for this request (rule-based; used for collectResPayload).
    private static func shouldCollectResponsePayload(for request: URLRequest, options: CoralogixExporterOptions) -> Bool {
        guard let configs = options.networkExtraConfig, !configs.isEmpty else { return false }
        let urlString = request.url?.absoluteString ?? ""
        return resolveConfigForUrl(urlString, configs: configs)?.collectResPayload ?? false
    }

    /// Returns whether request body should be captured for this request (rule-based; used for collectReqPayload).
    private static func shouldCollectRequestPayload(for request: URLRequest, options: CoralogixExporterOptions) -> Bool {
        guard let configs = options.networkExtraConfig, !configs.isEmpty else { return false }
        let urlString = request.url?.absoluteString ?? ""
        return resolveConfigForUrl(urlString, configs: configs)?.collectReqPayload ?? false
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
        
        // CRITICAL: Add session attributes to network spans
        // Without these, each network log creates a new random session ID
        // This is a critical bug - network logs must share the same session as other events
        if let sessionMetadata = self.sessionManager?.sessionMetadata {
            spanBuilder.setAttribute(key: Keys.sessionId.rawValue, value: sessionMetadata.sessionId)
            spanBuilder.setAttribute(key: Keys.sessionCreationDate.rawValue, value: String(Int(sessionMetadata.sessionCreationDate)))
        }

    }
    
    private func receivedResponse(response: URLResponse, data: DataOrFile?, span: any Span, request: URLRequest?) {
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
            Log.w("[Coralogix] CoralogixExporterOptions unexpectedly nil during network response handling — skipping span enrichment")
            return
        }
        
        let userContext = options.userContext

        span.setAttribute(key: Keys.userId.rawValue, value: userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: userContext?.userEmail ?? "")
        span.setAttribute(key: Keys.environment.rawValue, value: options.environment)

        // Network capture: allowlisted request/response headers when a rule matches (CX-33233)
        guard let configs = options.networkExtraConfig, !configs.isEmpty else { return }
        let requestUrl = request?.url?.absoluteString ?? (response as? HTTPURLResponse)?.url?.absoluteString ?? ""
        // Empty or invalid requestUrl → resolveConfigForUrl returns nil; no header capture.
        guard let rule = resolveConfigForUrl(requestUrl, configs: configs) else { return }

        // Request headers (allowlisted by rule.reqHeaders)
        if let reqHeaders = rule.reqHeaders, let req = request, let allReq = req.allHTTPHeaderFields, !allReq.isEmpty {
            let filtered = NetworkCaptureRule.filterHeaders(allReq, allowlist: reqHeaders)
            if !filtered.isEmpty {
                let dictAny = Dictionary(uniqueKeysWithValues: filtered.map { ($0.key, $0.value as Any) })
                let json = Helper.convertDictionayToJsonString(dict: dictAny)
                span.setAttribute(key: Keys.requestHeaders.rawValue, value: AttributeValue.string(json))
            }
        }
        // Response headers (allowlisted by rule.resHeaders)
        if let resHeaders = rule.resHeaders, let httpResponse = response as? HTTPURLResponse {
            let allRes = NetworkCaptureRule.responseHeadersDictionary(from: httpResponse)
            let filtered = NetworkCaptureRule.filterHeaders(allRes, allowlist: resHeaders)
            if !filtered.isEmpty {
                let dictAny = Dictionary(uniqueKeysWithValues: filtered.map { ($0.key, $0.value as Any) })
                let json = Helper.convertDictionayToJsonString(dict: dictAny)
                span.setAttribute(key: Keys.responseHeaders.rawValue, value: AttributeValue.string(json))
            }
        }
        // Response body (CX-33234): stringify by content-type, 1024-char limit (drop if over, no truncation)
        // dataOrFile can be Data or Optional(Data) depending on completion-handler signature, so we unwrap.
        if rule.collectResPayload, let responseData = NetworkCaptureRule.responseData(from: data), let httpResponse = response as? HTTPURLResponse {
            let headers = NetworkCaptureRule.responseHeadersDictionary(from: httpResponse)
            let contentType = headers.first { $0.key.lowercased() == "content-type" }?.value
            if let payload = NetworkCaptureRule.stringifyBody(data: responseData, contentType: contentType) {
                span.setAttribute(key: Keys.responsePayload.rawValue, value: AttributeValue.string(payload))
                Log.d("[Coralogix] response_payload set on span (\(payload.count) chars). See network_request_context.response_payload in RUM.")
            } else {
                Log.d("[Coralogix] response_payload skipped: stringifyBody returned nil (contentType: \(contentType ?? "nil"), dataLen: \(responseData.count))")
            }
        } else if rule.collectResPayload {
            Log.d("[Coralogix] response_payload skipped: no Data (type: \(type(of: data))) or response not HTTPURLResponse")
        }
    }
    
    // MARK: - Hybrid Network API

    /// Implementation called by `CoralogixRum.setNetworkRequestContext(dictionary:)`.
    internal func reportHybridNetworkRequest(_ dictionary: [String: Any]) {
        guard validateHybridNetworkRequest(dictionary) else { return }

        let span = getSpan()

        let statusCodeInt = coerceToInt(dictionary[Keys.statusCode.rawValue])
        if let status = statusCodeInt {
            let logSeverity: CoralogixLogSeverity = status >= 400 ? .error : .info
            span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(logSeverity.rawValue))
        }

        span.setAttribute(key: SemanticAttributes.httpUrl.rawValue, value: dictionary[Keys.url.rawValue] as? String ?? "")
        span.setAttribute(key: SemanticAttributes.netPeerName.rawValue, value: dictionary[Keys.host.rawValue] as? String ?? "")
        span.setAttribute(key: SemanticAttributes.httpMethod.rawValue, value: dictionary[Keys.method.rawValue] as? String ?? "")
        if let status = statusCodeInt {
            span.setAttribute(key: SemanticAttributes.httpStatusCode.rawValue, value: status)
        }
        span.setAttribute(key: SemanticAttributes.httpResponseBodySize.rawValue, value: dictionary[Keys.httpResponseBodySize.rawValue] as? Int ?? 0)
        span.setAttribute(key: SemanticAttributes.httpTarget.rawValue, value: dictionary[Keys.fragments.rawValue] as? String ?? "")
        span.setAttribute(key: SemanticAttributes.httpScheme.rawValue, value: dictionary[Keys.schema.rawValue] as? String ?? "")
        span.setAttribute(key: Keys.customSpanId.rawValue, value: dictionary[Keys.customSpanId.rawValue] as? String ?? "")
        span.setAttribute(key: Keys.customTraceId.rawValue, value: dictionary[Keys.customTraceId.rawValue] as? String ?? "")

        if let reqHeaders = dictionary[Keys.requestHeaders.rawValue] as? String, !reqHeaders.isEmpty {
            span.setAttribute(key: Keys.requestHeaders.rawValue, value: AttributeValue.string(reqHeaders))
        }
        if let resHeaders = dictionary[Keys.responseHeaders.rawValue] as? String, !resHeaders.isEmpty {
            span.setAttribute(key: Keys.responseHeaders.rawValue, value: AttributeValue.string(resHeaders))
        }
        if let reqPayload = dictionary[Keys.requestPayload.rawValue] as? String, !reqPayload.isEmpty {
            span.setAttribute(key: Keys.requestPayload.rawValue, value: AttributeValue.string(reqPayload))
        }
        if let resPayload = dictionary[Keys.responsePayload.rawValue] as? String, !resPayload.isEmpty {
            span.setAttribute(key: Keys.responsePayload.rawValue, value: AttributeValue.string(resPayload))
        }

        span.end()
    }

    /// Validates the hybrid network request dictionary. Returns false when required fields are missing or invalid (event is dropped and a warning is logged).
    private func validateHybridNetworkRequest(_ dictionary: [String: Any]) -> Bool {
        guard let url = dictionary[Keys.url.rawValue] as? String,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.w("setNetworkRequestContext: missing or invalid required key '\(Keys.url.rawValue)' — event dropped")
            return false
        }
        return true
    }

    private func getSpan() -> any Span {
        return makeSpan(event: .networkRequest, source: .fetch, severity: .info)
    }

    /// Coerces hybrid payload value (Int, Double, NSNumber, String) to Int for status_code.
    /// Returns nil for non-numeric or out-of-range (outside 100...599) values.
    internal func coerceToInt(_ value: Any?) -> Int? {
        guard let value else { return nil }
        let raw: Int
        if let i = value as? Int {
            raw = i
        } else if let d = value as? Double, let i = Int(exactly: d) {
            raw = i
        } else if let n = value as? NSNumber, let i = Int(exactly: n.doubleValue) {
            raw = i
        } else if let s = value as? String {
            if let i = Int(s) {
                raw = i
            } else if let d = Double(s), let i = Int(exactly: d) {
                raw = i
            } else {
                return nil
            }
        } else {
            return nil
        }
        return (100...599).contains(raw) ? raw : nil
    }
}
