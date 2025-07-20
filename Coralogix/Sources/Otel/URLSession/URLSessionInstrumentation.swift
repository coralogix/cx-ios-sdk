/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoralogixInternal

private var idKey: Void?

/// Lock to prevent concurrent calls to injectInNSURLClasses()
private let injectLock = NSLock()
private var didInject = false

struct NetworkRequestState {
    var request: URLRequest?
    var dataProcessed: Data?
    
    mutating func setRequest(_ request: URLRequest) {
        self.request = request
    }
    
    mutating func setData(_ data: Data) {
        dataProcessed = data
    }
}

public class URLSessionInstrumentation {
    private var requestMap = [String: NetworkRequestState]()
    
    var configuration: URLSessionInstrumentationConfiguration
    
    private let queue = DispatchQueue(label: "io.opentelemetry.ddnetworkinstrumentation")
    
    static var instrumentedKey = "io.opentelemetry.instrumentedCall"
    
    static let avAssetDownloadTask: AnyClass? = NSClassFromString("__NSCFBackgroundAVAssetDownloadTask")
    
    public private(set) var tracer: Tracer
    
    public var startedRequestSpans: [any Span] {
        var spans = [any Span]()
        URLSessionLogger.runningSpansQueue.sync {
            spans = Array(URLSessionLogger.runningSpans.values)
        }
        return spans
    }
    
    public init(configuration: URLSessionInstrumentationConfiguration) {
        self.configuration = configuration
        tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: "NSURLSession", instrumentationVersion: "0.0.1")
        self.injectInNSURLClasses()
    }
    
    private func injectInNSURLClasses() {
        injectLock.lock()
        defer { injectLock.unlock() }
        
        guard !didInject else { return }
        didInject = true
        
#if swift(<5.7)
        let selectors = [
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:)),
            #selector(URLSessionDataDelegate.urlSession(_:task:didCompleteWithError:)),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:)! as (URLSessionDataDelegate) -> (URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:)! as (URLSessionDataDelegate) -> (URLSession, URLSessionDataTask, URLSessionStreamTask) -> Void),
        ]
#else
        let selectors = [
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:)),
            #selector(URLSessionDataDelegate.urlSession(_:task:didCompleteWithError:)),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:) as (URLSessionDataDelegate) -> ((URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void)?),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:) as (URLSessionDataDelegate) -> ((URLSession, URLSessionDataTask, URLSessionStreamTask) -> Void)?),
        ]
#endif
        
        let classes = configuration.delegateClassesToInstrument ?? InstrumentationUtils.objc_getClassList()
        
        for theClass in classes {
            guard theClass != Self.self else { continue }
            
            // MARK: [FIX] Validate Objective-C class (prevents crash in class_copyMethodList)
            guard class_getSuperclass(theClass) != nil else {
                //Log.d("Skipping non-ObjC class: \(theClass)")
                continue
            }
            
            guard !class_isMetaClass(theClass) else {
                //Log.d("Skipping metaclass: \(theClass)")
                continue
            }
            
            var methodCount: UInt32 = 0
            guard let methodListPointer = class_copyMethodList(theClass, &methodCount) else { continue }
            defer { free(methodListPointer) }
            
            let methodList = UnsafeBufferPointer(start: methodListPointer, count: Int(methodCount))
            
            for selector in selectors {
                if methodList.contains(where: { method_getName($0) == selector }) {
                    injectIntoDelegateClass(cls: theClass)
                    break
                }
            }
        }
        
        if #available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            injectIntoNSURLSessionCreateTaskMethods()
        }
        injectIntoNSURLSessionCreateTaskWithParameterMethods()
        injectIntoNSURLSessionAsyncDataAndDownloadTaskMethods()
        injectIntoNSURLSessionAsyncUploadTaskMethods()
        injectIntoNSURLSessionTaskResume()
    }
    
    private func injectIntoDelegateClass(cls: AnyClass) {
        // Sessions
        injectTaskDidReceiveDataIntoDelegateClass(cls: cls)
        injectTaskDidReceiveResponseIntoDelegateClass(cls: cls)
        injectTaskDidCompleteWithErrorIntoDelegateClass(cls: cls)
        injectRespondsToSelectorIntoDelegateClass(cls: cls)
        // For future use
        if #available(OSX 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
            injectTaskDidFinishCollectingMetricsIntoDelegateClass(cls: cls)
        }
        
        // Data tasks
        injectDataTaskDidBecomeDownloadTaskIntoDelegateClass(cls: cls)
    }
    
    private func injectIntoNSURLSessionCreateTaskMethods() {
        let cls = URLSession.self
        let selectors: [Selector] = [
            #selector(URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask),
            #selector(URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask),
            #selector(URLSession.uploadTask(withStreamedRequest:)),
            #selector(URLSession.downloadTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDownloadTask),
            #selector(URLSession.downloadTask(with:) as (URLSession) -> (URL) -> URLSessionDownloadTask),
            #selector(URLSession.downloadTask(withResumeData:)),
        ]
        
        for selector in selectors {
            guard let method = class_getInstanceMethod(cls, selector) else {
                Log.e("Method \(selector) not found in \(cls)")
                continue
            }
            
            // MARK: [FIX] Guard for IMP existence
            let originalIMP = method_getImplementation(method)
            
            // MARK: [FIX] Safe block-based swizzling
            let instrumentation = self
            let block: @convention(block) (URLSession, AnyObject) -> URLSessionTask = { session, argument in
                // MARK: [FIX] Reentrancy guard
                let key = "cx.reentrancy.\(selector)"
                if objc_getAssociatedObject(session, key) != nil {
                    return unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, AnyObject) -> URLSessionTask).self)(session, selector, argument)
                }
                objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                defer { objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
                
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, Any) -> URLSessionTask).self)
                let sessionTaskId = UUID().uuidString
                var task: URLSessionTask
                
                if let url = argument as? URL {
                    let request = URLRequest(url: url)
                    let instrumented = URLSessionLogger.processAndLogRequest(request, sessionTaskId: sessionTaskId, instrumentation: self, shouldInjectHeaders: true)
                    task = castedIMP(session, selector, instrumented ?? request)
                } else if let request = argument as? URLRequest {
                    let instrumented = URLSessionLogger.processAndLogRequest(request, sessionTaskId: sessionTaskId, instrumentation: self, shouldInjectHeaders: true)
                    task = castedIMP(session, selector, instrumented ?? request)
                } else {
                    task = castedIMP(session, selector, argument)
                }
                instrumentation.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            
            // MARK: [FIX] Guard method_setImplementation
            let swizzledIMP = imp_implementationWithBlock(block as Any)
            _ = method_setImplementation(method, swizzledIMP)
        }
    }
    
    private func injectIntoNSURLSessionCreateTaskWithParameterMethods() {
        typealias UploadWithDataIMP = @convention(c) (URLSession, Selector, URLRequest, Data?) -> URLSessionTask
        typealias UploadWithFileIMP = @convention(c) (URLSession, Selector, URLRequest, URL) -> URLSessionTask
        
        let cls = URLSession.self
        
        // MARK: Swizzle `uploadTask(with:from:)`
        if let method = class_getInstanceMethod(cls, #selector(URLSession.uploadTask(with:from:))) {
            let originalIMP = method_getImplementation(method)
            let imp = unsafeBitCast(originalIMP, to: UploadWithDataIMP.self)
            
            let block: @convention(block) (URLSession, URLRequest, Data?) -> URLSessionTask = { [weak self] session, request, data in
                guard let instrumentation = self else {
                    return imp(session, #selector(URLSession.uploadTask(with:from:)), request, data)
                }
                
                let sessionTaskId = UUID().uuidString
                let instrumentedRequest = URLSessionLogger.processAndLogRequest(
                    request,
                    sessionTaskId: sessionTaskId,
                    instrumentation: instrumentation,
                    shouldInjectHeaders: true
                )
                
                let task = imp(session, #selector(URLSession.uploadTask(with:from:)), instrumentedRequest ?? request, data)
                instrumentation.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            let swizzledIMP = imp_implementationWithBlock(block)
            method_setImplementation(method, swizzledIMP)
        }
        
        // MARK: Swizzle `uploadTask(with:fromFile:)`
        if let method = class_getInstanceMethod(cls, #selector(URLSession.uploadTask(with:fromFile:))) {
            let originalIMP = method_getImplementation(method)
            let imp = unsafeBitCast(originalIMP, to: UploadWithFileIMP.self)
            
            let block: @convention(block) (URLSession, URLRequest, URL) -> URLSessionTask = { [weak self] session, request, fileURL in
                guard let instrumentation = self else {
                    return imp(session, #selector(URLSession.uploadTask(with:fromFile:)), request, fileURL)
                }
                
                let sessionTaskId = UUID().uuidString
                let instrumentedRequest = URLSessionLogger.processAndLogRequest(
                    request,
                    sessionTaskId: sessionTaskId,
                    instrumentation: instrumentation,
                    shouldInjectHeaders: true
                )
                
                let task = imp(session, #selector(URLSession.uploadTask(with:fromFile:)), instrumentedRequest ?? request, fileURL)
                instrumentation.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            let swizzledIMP = imp_implementationWithBlock(block)
            method_setImplementation(method, swizzledIMP)
        }
    }
    
    private func injectIntoNSURLSessionAsyncDataAndDownloadTaskMethods() {
        let cls = URLSession.self
        [
            #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask),
            #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask),
            #selector(URLSession.downloadTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask),
            #selector(URLSession.downloadTask(with:completionHandler:) as (URLSession) -> (URL, @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask),
            #selector(URLSession.downloadTask(withResumeData:completionHandler:)),
        ].forEach {
            let selector = $0
            guard let original = class_getInstanceMethod(cls, selector) else {
                Log.d("injectInto \(selector.description) failed")
                return
            }
            var originalIMP: IMP?
            
            let block: @convention(block) (URLSession, AnyObject, ((Any?, URLResponse?, Error?) -> Void)?) -> URLSessionTask = { session, argument, completion in
                
                if let url = argument as? URL {
                    let request = URLRequest(url: url)
                    
                    if self.configuration.shouldInjectTracingHeaders?(request) ?? true {
                        if selector == #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask) {
                            if let completion = completion {
                                return session.dataTask(with: request, completionHandler: completion)
                            } else {
                                return session.dataTask(with: request)
                            }
                        } else {
                            if let completion = completion {
                                return session.downloadTask(with: request, completionHandler: completion)
                            } else {
                                return session.downloadTask(with: request)
                            }
                        }
                    }
                }
                
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, Any, ((Any?, URLResponse?, Error?) -> Void)?) -> URLSessionDataTask).self)
                var task: URLSessionTask!
                let sessionTaskId = UUID().uuidString
                
                var completionBlock = completion
                let instrumentation = self
                
                if completionBlock != nil {
                    if objc_getAssociatedObject(argument, &idKey) == nil {
                        let completionWrapper: (Any?, URLResponse?, Error?) -> Void = { object, response, error in
                            if error != nil {
                                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                                URLSessionLogger.logError(error!, dataOrFile: object, statusCode: status, instrumentation: self, sessionTaskId: sessionTaskId)
                            } else {
                                if let response = response {
                                    URLSessionLogger.logResponse(response, dataOrFile: object, instrumentation: self, sessionTaskId: sessionTaskId)
                                }
                            }
                            if let completion = completion {
                                completion(object, response, error)
                            } else {
                                (session.delegate as? URLSessionTaskDelegate)?.urlSession?(session, task: task, didCompleteWithError: error)
                            }
                        }
                        completionBlock = completionWrapper
                    }
                }
                
                if let request = argument as? URLRequest, objc_getAssociatedObject(argument, &idKey) == nil {
                    let instrumentedRequest = URLSessionLogger.processAndLogRequest(request, sessionTaskId: sessionTaskId, instrumentation: self, shouldInjectHeaders: true)
                    task = castedIMP(session, selector, instrumentedRequest ?? request, completionBlock)
                } else {
                    task = castedIMP(session, selector, argument, completionBlock)
                    if objc_getAssociatedObject(argument, &idKey) == nil,
                       let currentRequest = task.currentRequest {
                        URLSessionLogger.processAndLogRequest(currentRequest, sessionTaskId: sessionTaskId, instrumentation: self, shouldInjectHeaders: false)
                    }
                }
                instrumentation.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
            originalIMP = method_setImplementation(original, swizzledIMP)
        }
    }
    
    private func injectIntoNSURLSessionAsyncUploadTaskMethods() {
        let cls = URLSession.self
        [
            #selector(URLSession.uploadTask(with:from:completionHandler:)),
            #selector(URLSession.uploadTask(with:fromFile:completionHandler:)),
        ].forEach {
            let selector = $0
            guard let original = class_getInstanceMethod(cls, selector) else {
                Log.d("injectInto \(selector.description) failed")
                return
            }
            var originalIMP: IMP?
            
            let instrumentation = self
            let block: @convention(block) (URLSession, URLRequest, AnyObject, ((Any?, URLResponse?, Error?) -> Void)?) -> URLSessionTask = { session, request, argument, completion in
                
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, URLRequest, AnyObject, ((Any?, URLResponse?, Error?) -> Void)?) -> URLSessionDataTask).self)
                
                var task: URLSessionTask!
                let sessionTaskId = UUID().uuidString
                
                var completionBlock = completion
                if objc_getAssociatedObject(argument, &idKey) == nil {
                    let completionWrapper: (Any?, URLResponse?, Error?) -> Void = { object, response, error in
                        if error != nil {
                            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                            URLSessionLogger.logError(error!, dataOrFile: object, statusCode: status, instrumentation: self, sessionTaskId: sessionTaskId)
                        } else {
                            if let response = response {
                                URLSessionLogger.logResponse(response, dataOrFile: object, instrumentation: self, sessionTaskId: sessionTaskId)
                            }
                        }
                        if let completion = completion {
                            completion(object, response, error)
                        } else {
                            (session.delegate as? URLSessionTaskDelegate)?.urlSession?(session, task: task, didCompleteWithError: error)
                        }
                    }
                    completionBlock = completionWrapper
                }
                
                let processedRequest = URLSessionLogger.processAndLogRequest(request, sessionTaskId: sessionTaskId, instrumentation: self, shouldInjectHeaders: true)
                task = castedIMP(session, selector, processedRequest ?? request, argument, completionBlock)
                
                instrumentation.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
            originalIMP = method_setImplementation(original, swizzledIMP)
        }
    }
    
    private static var resumeSwizzleKey: UInt8 = 0
    
    private func injectIntoNSURLSessionTaskResume() {
        typealias ResumeIMPType = @convention(c) (AnyObject, Selector) -> Void
        var methodsToSwizzle = [(cls: AnyClass, sel: Selector, method: Method)]()
        
        // Helper: Adds method for class + selector if it exists
        func appendMethodIfExists(for cls: AnyClass, selector: Selector) {
            if let method = class_getInstanceMethod(cls, selector) {
                methodsToSwizzle.append((cls, selector, method))
            }
        }
        
        // Swizzle URLSessionTask
        appendMethodIfExists(for: URLSessionTask.self, selector: #selector(URLSessionTask.resume))
        
        // Swizzle internal Apple class (if exists)
        if let cfURLSession = NSClassFromString("__NSCFURLSessionTask") {
            appendMethodIfExists(for: cfURLSession, selector: NSSelectorFromString("resume"))
        }
        
        // Swizzle AFNetworking (if used)
        if NSClassFromString("AFURLSessionManager") != nil {
            let classes = InstrumentationUtils.objc_getSafeClassList(
                ignoredPrefixes: configuration.ignoredClassPrefixes
            )
            if classes.isEmpty {
                Log.d("[URLSessionInstrumentation] No safe classes found for af_resume swizzling")
            } else {
                for cls in classes {
                    appendMethodIfExists(for: cls, selector: NSSelectorFromString("af_resume"))
                }
            }
        } else {
            Log.d("[URLSessionInstrumentation] AFNetworking not detected, skipping swizzling")
        }
        
        
        for (cls, selector, method) in methodsToSwizzle {
            
            // ✅ Safety check: ensure method signature is void-return, no args
            guard let typeEncoding = method_getTypeEncoding(method),
                  String(cString: typeEncoding) == "v@:" else {
                Log.d("[URLSessionInstrumentation] Skipping method \(selector) on \(cls) due to invalid signature")
                continue // Skip this method – wrong signature
            }
            
            let originalIMP = method_getImplementation(method)
            
            let block: @convention(block) (AnyObject) -> Void = { [weak self] task in
                guard let self = self else { return }
                
                // Call hook
                if let urlSessionTask = task as? URLSessionTask {
                    self.urlSessionTaskWillResume(urlSessionTask)
                }
                
                objc_setAssociatedObject(task, &Self.resumeSwizzleKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                // Call original implementation
                let original: ResumeIMPType = unsafeBitCast(originalIMP, to: ResumeIMPType.self)
                original(task, selector)
                
                objc_setAssociatedObject(task, &Self.resumeSwizzleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            
            let swizzledIMP = imp_implementationWithBlock(block as Any)
            method_setImplementation(method, swizzledIMP)
        }
    }
    
    // Delegate methods
    private func injectTaskDidReceiveDataIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:))
        guard let original = class_getInstanceMethod(cls, selector) else {
            return
        }
        var originalIMP: IMP?
        let block: @convention(block) (Any, URLSession, URLSessionDataTask, Data) -> Void = { object, session, dataTask, data in
            if objc_getAssociatedObject(session, &idKey) == nil {
                self.urlSession(session, dataTask: dataTask, didReceive: data)
            }
            let key = String(selector.hashValue)
            objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, URLSession, URLSessionDataTask, Data) -> Void).self)
            castedIMP(object, selector, session, dataTask, data)
            objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    private func injectTaskDidReceiveResponseIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:))
        guard let original = class_getInstanceMethod(cls, selector) else {
            return
        }
        var originalIMP: IMP?
        let block: @convention(block) (Any, URLSession, URLSessionDataTask, URLResponse, @escaping (URLSession.ResponseDisposition) -> Void) -> Void = { object, session, dataTask, response, completion in
            if objc_getAssociatedObject(session, &idKey) == nil {
                self.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completion)
            }
            let key = String(selector.hashValue)
            objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, URLSession, URLSessionDataTask, URLResponse, @escaping (URLSession.ResponseDisposition) -> Void) -> Void).self)
            castedIMP(object, selector, session, dataTask, response, completion)
            objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    private func injectTaskDidCompleteWithErrorIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(URLSessionDataDelegate.urlSession(_:task:didCompleteWithError:))
        guard let original = class_getInstanceMethod(cls, selector) else {
            return
        }
        var originalIMP: IMP?
        let instrumentation = self
        let block: @convention(block) (Any, URLSession, URLSessionTask, Error?) -> Void = { object, session, task, error in
            if objc_getAssociatedObject(session, &idKey) == nil {
                instrumentation.urlSession(session, task: task, didCompleteWithError: error)
            }
            let key = String(selector.hashValue)
            objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, URLSession, URLSessionTask, Error?) -> Void).self)
            castedIMP(object, selector, session, task, error)
            objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    private func injectTaskDidFinishCollectingMetricsIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:))
        guard let original = class_getInstanceMethod(cls, selector) else {
            let block: @convention(block) (Any, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void = { _, session, task, metrics in
                self.urlSession(session, task: task, didFinishCollecting: metrics)
            }
            let imp = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
            class_addMethod(cls, selector, imp, "@@@")
            return
        }
        var originalIMP: IMP?
        let block: @convention(block) (Any, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void = { object, session, task, metrics in
            if objc_getAssociatedObject(session, &idKey) == nil {
                self.urlSession(session, task: task, didFinishCollecting: metrics)
            }
            let key = String(selector.hashValue)
            objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void).self)
            castedIMP(object, selector, session, task, metrics)
            objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    func injectRespondsToSelectorIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(NSObject.responds(to:))
        guard let original = class_getInstanceMethod(cls, selector),
              InstrumentationUtils.instanceRespondsAndImplements(cls: cls, selector: selector)
        else {
            return
        }
        
        var originalIMP: IMP?
        let block: @convention(block) (Any, Selector) -> Bool = { object, respondsTo in
            if respondsTo == #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:)) {
                return true
            }
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, Selector) -> Bool).self)
            return castedIMP(object, selector, respondsTo)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    private func injectDataTaskDidBecomeDownloadTaskIntoDelegateClass(cls: AnyClass) {
#if swift(<5.7)
        let selector = #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:)! as (URLSessionDataDelegate) -> (URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void)
#else
        let selector = #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:) as (URLSessionDataDelegate) -> ((URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void)?)
#endif
        guard let original = class_getInstanceMethod(cls, selector) else {
            return
        }
        var originalIMP: IMP?
        let block: @convention(block) (Any, URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void = { object, session, dataTask, downloadTask in
            if objc_getAssociatedObject(session, &idKey) == nil {
                self.urlSession(session, dataTask: dataTask, didBecome: downloadTask)
            }
            let key = String(selector.hashValue)
            objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void).self)
            castedIMP(object, selector, session, dataTask, downloadTask)
            objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    // URLSessionTask methods
    private func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard configuration.shouldRecordPayload?(session) ?? false else { return }
        guard let taskId = objc_getAssociatedObject(dataTask, &idKey) as? String else {
            return
        }
        let dataCopy = data
        queue.sync {
            if (requestMap[taskId]?.request) != nil {
                createRequestState(for: taskId)
                if requestMap[taskId]?.dataProcessed == nil {
                    requestMap[taskId]?.dataProcessed = Data()
                }
                requestMap[taskId]?.dataProcessed?.append(dataCopy)
            }
        }
    }
    
    private func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard configuration.shouldRecordPayload?(session) ?? false else { return }
        guard let taskId = objc_getAssociatedObject(dataTask, &idKey) as? String else {
            return
        }
        queue.sync {
            if (requestMap[taskId]?.request) != nil {
                createRequestState(for: taskId)
                if response.expectedContentLength < 0 {
                    requestMap[taskId]?.dataProcessed = Data()
                } else {
                    requestMap[taskId]?.dataProcessed = Data(capacity: Int(response.expectedContentLength))
                }
            }
        }
    }
    
    private func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskId = objc_getAssociatedObject(task, &idKey) as? String else {
            return
        }
        var requestState: NetworkRequestState?
        queue.sync {
            requestState = requestMap[taskId]
            if requestState != nil {
                requestMap[taskId] = nil
            }
        }
        if let error = error {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            URLSessionLogger.logError(error, dataOrFile: requestState?.dataProcessed, statusCode: status, instrumentation: self, sessionTaskId: taskId)
        } else if let response = task.response {
            URLSessionLogger.logResponse(response, dataOrFile: requestState?.dataProcessed, instrumentation: self, sessionTaskId: taskId)
        }
    }
    
    private func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        guard let taskId = objc_getAssociatedObject(dataTask, &idKey) as? String else {
            return
        }
        setIdKey(value: taskId, for: downloadTask)
    }
    
    private func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let taskId = objc_getAssociatedObject(task, &idKey) as? String else {
            return
        }
        var requestState: NetworkRequestState?
        queue.sync {
            requestState = requestMap[taskId]
            
            if requestState?.request != nil {
                requestMap[taskId] = nil
            }
        }
        
        guard requestState?.request != nil else {
            return
        }
        
        /// Code for instrumenting collection should be written here
        if let error = task.error {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            URLSessionLogger.logError(error, dataOrFile: requestState?.dataProcessed, statusCode: status, instrumentation: self, sessionTaskId: taskId)
        } else if let response = task.response {
            URLSessionLogger.logResponse(response, dataOrFile: requestState?.dataProcessed, instrumentation: self, sessionTaskId: taskId)
        }
    }
    
    private func urlSessionTaskWillResume(_ task: URLSessionTask) {
        // AV Asset Tasks cannot be auto instrumented, they dont include request attributes, skip them
        if let avAssetTaskClass = Self.avAssetDownloadTask,
           task.isKind(of: avAssetTaskClass) {
            return
        }
        
        let taskId = idKeyForTask(task)
        if let request = task.currentRequest {
            queue.sync {
                if requestMap[taskId] == nil {
                    requestMap[taskId] = NetworkRequestState()
                }
                requestMap[taskId]?.setRequest(request)
            }
            
            if #available(OSX 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                guard Task.basePriority != nil else {
                    return
                }
                let instrumentedRequest = URLSessionLogger.processAndLogRequest(request, sessionTaskId: taskId, instrumentation: self, shouldInjectHeaders: true)
                task.setValue(instrumentedRequest, forKey: "currentRequest")
                self.setIdKey(value: taskId, for: task)
                
                // If not inside a Task basePriority is nil
                if task.delegate == nil {
                    task.delegate = FakeDelegate()
                }
            }
        }
    }
    
    // Helpers
    private func idKeyForTask(_ task: URLSessionTask) -> String {
        var id = objc_getAssociatedObject(task, &idKey) as? String
        if id == nil {
            id = UUID().uuidString
            objc_setAssociatedObject(task, &idKey, id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return id!
    }
    
    private func setIdKey(value: String, for task: URLSessionTask) {
        objc_setAssociatedObject(task, &idKey, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    private func createRequestState(for id: String) {
        var state = requestMap[id]
        if requestMap[id] == nil {
            state = NetworkRequestState()
            requestMap[id] = state
        }
    }
}

class FakeDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {}
}
