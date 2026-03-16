/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public typealias DataOrFile = Any
public typealias SessionTaskId = String
public typealias HTTPStatus = Int

public struct URLSessionInstrumentationConfiguration {
    public init(shouldRecordPayload: ((URLSession) -> (Bool)?)? = nil,
                shouldInstrument: ((URLRequest) -> (Bool)?)? = nil,
                nameSpan: ((URLRequest) -> (String)?)? = nil,
                spanCustomization: ((URLRequest, SpanBuilder) -> Void)? = nil,
                shouldInjectTracingHeaders: ((URLRequest) -> (Bool)?)? = nil,
                shouldCollectResponsePayload: ((URLRequest) -> Bool)? = nil,
                shouldCollectRequestPayload: ((URLRequest) -> Bool)? = nil,
                injectCustomHeaders: ((inout URLRequest, (any Span)?) -> Void)? = nil,
                createdRequest: ((URLRequest, any Span) -> Void)? = nil,
                receivedResponse: ((URLResponse, DataOrFile?, any Span, URLRequest?) -> Void)? = nil,
                receivedError: ((Error, DataOrFile?, HTTPStatus, any Span) -> Void)? = nil,
                delegateClassesToInstrument: [AnyClass]? = nil,
                tracer: Tracer? = nil) {
        self.shouldRecordPayload = shouldRecordPayload
        self.shouldInstrument = shouldInstrument
        self.shouldInjectTracingHeaders = shouldInjectTracingHeaders
        self.shouldCollectResponsePayload = shouldCollectResponsePayload
        self.shouldCollectRequestPayload = shouldCollectRequestPayload
        self.injectCustomHeaders = injectCustomHeaders
        self.nameSpan = nameSpan
        self.spanCustomization = spanCustomization
        self.createdRequest = createdRequest
        self.receivedResponse = receivedResponse
        self.receivedError = receivedError
        self.delegateClassesToInstrument = delegateClassesToInstrument
        self.tracer = tracer ??
             OpenTelemetry.instance.tracerProvider.get(instrumentationName: "NSURLSession", instrumentationVersion: "0.0.1")
    }
    
    public var tracer: Tracer

    // Instrumentation Callbacks

    /// Implement this callback to filter which requests you want to instrument, all by default
    public var shouldInstrument: ((URLRequest) -> (Bool)?)?

    /// Implement this callback if you want the session to record payload data, false by default.
    /// This callback is only necessary when using session delegate
    public var shouldRecordPayload: ((URLSession) -> (Bool)?)?

    /// When non-nil and returning true for a request, response body is buffered (delegate path) and stringified for capture.
    /// Used for rule-based response payload capture (e.g. NetworkCaptureRule.collectResPayload). Prefer over speculative buffering.
    public var shouldCollectResponsePayload: ((URLRequest) -> Bool)?

    /// When non-nil and returning true for a request, request body is captured and stringified (1024-char limit).
    /// Used for rule-based request payload capture (e.g. NetworkCaptureRule.collectReqPayload). Body is read at task-creation time.
    public var shouldCollectRequestPayload: ((URLRequest) -> Bool)?

    /// Implement this callback to filter which requests you want to inject headers to follow the trace,
    /// also must implement it if you want to inject custom headers
    /// Instruments all requests by default
    public var shouldInjectTracingHeaders: ((URLRequest) -> (Bool)?)?

    /// Implement this callback to inject custom headers or modify the request in any other way
    public var injectCustomHeaders: ((inout URLRequest, (any Span)?) -> Void)?

    /// Implement this callback to override the default span name for a given request, return nil to use default.
    /// default name: `HTTP {method}` e.g. `HTTP PUT`
    public var nameSpan: ((URLRequest) -> (String)?)?

    /// Implement this callback to customize the span, such as by adding a parent, a link, attributes, etc
    public var spanCustomization: ((URLRequest, SpanBuilder) -> Void)?

    ///  Called before the span is created, it allows to add extra information to the Span
    public var createdRequest: ((URLRequest, any Span) -> Void)?

    ///  Called before the span is ended, it allows to add extra information to the Span.
    ///  The optional URLRequest is the original request (when available) for use in network capture (e.g. header filtering).
    public var receivedResponse: ((URLResponse, DataOrFile?, any Span, URLRequest?) -> Void)?

    ///  Called before the span is ended, it allows to add extra information to the Span
    public var receivedError: ((Error, DataOrFile?, HTTPStatus, any Span) -> Void)?
    
    /// The array of URLSession delegate classes that will be instrumented by the library.
    /// NOTE: Auto-detection has been disabled. You must explicitly provide classes to enable delegate swizzling.
    /// If nil or empty, delegate methods will not be swizzled (URLSession method swizzling still works).
    public var delegateClassesToInstrument: [AnyClass]?
}
