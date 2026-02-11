/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoralogixInternal

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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

private var idKey: Void?

public class URLSessionInstrumentation {
    private var requestMap = [String: NetworkRequestState]()
    
    private var _configuration: URLSessionInstrumentationConfiguration
    public var configuration: URLSessionInstrumentationConfiguration {
        get { configurationQueue.sync { _configuration } }
    }
    
    private let queue = DispatchQueue(label: "io.opentelemetry.ddnetworkinstrumentation", attributes: .concurrent)
    private let configurationQueue = DispatchQueue(label: "io.opentelemetry.configuration")
    
    static var instrumentedKey = "io.opentelemetry.instrumentedCall"
    private static var delegateSwizzleKey: UInt8 = 0
    private static var loggedKey: UInt8 = 0  // Deduplication flag for hybrid approach
    private static var setStateSwizzleKey: UInt8 = 0
    
    static let AVTaskClassList: [AnyClass] = [
        "__NSCFBackgroundAVAggregateAssetDownloadTask",
        "__NSCFBackgroundAVAssetDownloadTask",
        "__NSCFBackgroundAVAggregateAssetDownloadTaskNoChildTask"
    ].compactMap { NSClassFromString($0) }
        
    public var startedRequestSpans: [any Span] {
        var spans = [any Span]()
        URLSessionLogger.runningSpansQueue.sync {
            spans = Array(URLSessionLogger.runningSpans.values)
        }
        return spans
    }
    
    public init(configuration: URLSessionInstrumentationConfiguration) {
        self._configuration = configuration
        self.injectInNSURLClasses()
    }
    
    private func injectInNSURLClasses() {
        // Only swizzle delegate classes if explicitly provided
        if let explicitClasses = configuration.delegateClassesToInstrument, !explicitClasses.isEmpty {
            Log.d("[URLSessionInstrumentation] Swizzling \(explicitClasses.count) explicitly provided delegate classes")
            swizzleExplicitDelegateClasses(explicitClasses)
        }
        
        // Always swizzle URLSession methods (no class scanning needed - safe)
        if #available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            injectIntoNSURLSessionCreateTaskMethods()
        }
        injectIntoNSURLSessionCreateTaskWithParameterMethods()
        injectIntoNSURLSessionAsyncDataAndDownloadTaskMethods()
        injectIntoNSURLSessionAsyncUploadTaskMethods()
        
        injectIntoNSURLSessionTaskResume()
        
        // Hybrid approach: Add setState: swizzling for universal coverage (Alamofire, etc.)
        injectIntoNSURLSessionTaskSetState()
    }
    
    private func swizzleExplicitDelegateClasses(_ classes: [AnyClass]) {
        let selectors = [
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:)),
            #selector(URLSessionDataDelegate.urlSession(_:task:didCompleteWithError:)),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:) as (URLSessionDataDelegate) -> ((URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void)?),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:) as (URLSessionDataDelegate) -> ((URLSession, URLSessionDataTask, URLSessionStreamTask) -> Void)?),
        ]
        
        var swizzledCount = 0
        
        for theClass in classes {
            guard class_getSuperclass(theClass) != nil else { 
                Log.w("[URLSessionInstrumentation] Skipping \(theClass) - no superclass")
                continue 
            }
            guard !class_isMetaClass(theClass) else { 
                Log.w("[URLSessionInstrumentation] Skipping \(theClass) - is metaclass")
                continue 
            }
            guard theClass != Self.self else { 
                Log.w("[URLSessionInstrumentation] Skipping \(theClass) - is self")
                continue 
            }
            guard class_conformsToProtocol(theClass, URLSessionTaskDelegate.self) ||
                    class_conformsToProtocol(theClass, URLSessionDataDelegate.self) else { 
                Log.w("[URLSessionInstrumentation] Skipping \(theClass) - doesn't conform to URLSessionDelegate protocols")
                continue 
            }
            
            // Check if already swizzled
            if objc_getAssociatedObject(theClass, &Self.delegateSwizzleKey) != nil {
                continue
            }
            
            // Check if class implements any of the selectors we want to swizzle
            var methodCount: UInt32 = 0
            guard let methodListPointer = class_copyMethodList(theClass, &methodCount) else { 
                Log.w("[URLSessionInstrumentation] Skipping \(theClass) - no methods found")
                continue 
            }
            defer { free(methodListPointer) }
            
            let methodList = UnsafeBufferPointer(start: methodListPointer, count: Int(methodCount))
            
            var hasTargetMethod = false
            for selector in selectors {
                if methodList.contains(where: { method_getName($0) == selector }) {
                    hasTargetMethod = true
                    break
                }
            }
            
            if hasTargetMethod {
                injectIntoDelegateClass(cls: theClass)
                objc_setAssociatedObject(theClass, &Self.delegateSwizzleKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                swizzledCount += 1
            } else {
                Log.w("[URLSessionInstrumentation] Skipping \(theClass) - no target delegate methods found")
            }
        }
        
        Log.d("[URLSessionInstrumentation] Successfully swizzled \(swizzledCount) of \(classes.count) explicit delegate classes")
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
        let cls: AnyClass = URLSession.self
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
            
            let originalIMP = method_getImplementation(method)
            let instrumentation = self
            let block: @convention(block) (URLSession, AnyObject) -> URLSessionTask = { session, argument in
                let key = "cx.reentrancy.\(selector)"
                if objc_getAssociatedObject(session, key) != nil {
                    return unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, AnyObject) -> URLSessionTask).self)(session, selector, argument)
                }
                objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                defer { objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
                
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, Any) -> URLSessionTask).self)
                let sessionTaskId = UUID().uuidString
                let bridged = self.bridgedArgumentForFactory(
                    selector: selector,
                    argument: argument,
                    sessionTaskId: sessionTaskId
                )

                let task = castedIMP(session, selector, bridged)
                instrumentation.setIdKey(value: sessionTaskId, for: task)
               
                if (session.delegate == nil) {
                    task.setValue(FakeDelegate(), forKey: "delegate")
                }
                
                // We want to identify background tasks
                if session.configuration.identifier != nil {
                    objc_setAssociatedObject(task, "IsBackground", true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
                return task
            }
            
            let swizzledIMP = imp_implementationWithBlock(block as Any)
            _ = method_setImplementation(method, swizzledIMP)
        }
    }
    
    private func isHTTPScheme(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func shouldInject(for request: URLRequest) -> Bool {
        configuration.shouldInjectTracingHeaders?(request) ?? true
    }
    
    @discardableResult
    private func instrumentRequest(
        _ request: URLRequest,
        sessionTaskId: String,
        injectHeaders: Bool
    ) -> URLRequest? {
        URLSessionLogger.processAndLogRequest(
            request,
            sessionTaskId: sessionTaskId,
            instrumentation: self,
            shouldInjectHeaders: injectHeaders
        )
    }
    
    private func coerceToRequest(_ argument: AnyObject) -> URLRequest? {
        if let req = argument as? URLRequest { return req }
        if let reqObjc = argument as? NSURLRequest { return reqObjc as URLRequest }
        if let url = argument as? URL { return URLRequest(url: url) }
        if let urlObjc = argument as? NSURL { return URLRequest(url: urlObjc as URL) }
        return nil
    }

    private func coerceToURL(_ argument: AnyObject) -> URL? {
        if let url = argument as? URL { return url }
        if let urlObjc = argument as? NSURL { return urlObjc as URL }
        if let req = argument as? URLRequest { return req.url }
        if let reqObjc = argument as? NSURLRequest { return reqObjc.url }
        return nil
    }
    
    private enum TaskFactoryOverload {
        case urlRequest        // dataTask(with: URLRequest), downloadTask(with: URLRequest), uploadTask(withStreamedRequest:)
        case url               // dataTask(with: URL), downloadTask(with: URL)
        case resumeData        // downloadTask(withResumeData:)
        case unknown
    }

    private func overloadKind(for selector: Selector) -> TaskFactoryOverload {
        if selector == #selector(URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask) ||
           selector == #selector(URLSession.downloadTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDownloadTask) ||
           selector == #selector(URLSession.uploadTask(withStreamedRequest:)) {
            return .urlRequest
        }
        if selector == #selector(URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask) ||
           selector == #selector(URLSession.downloadTask(with:) as (URLSession) -> (URL) -> URLSessionDownloadTask) {
            return .url
        }
        if selector == #selector(URLSession.downloadTask(withResumeData:)) {
            return .resumeData
        }
        return .unknown
    }
    
    private func bridgedArgumentForFactory(
        selector: Selector,
        argument: AnyObject,
        sessionTaskId: String
    ) -> AnyObject {
        switch overloadKind(for: selector) {

        case .urlRequest:
            // Signature expects NSURLRequest*
            if let originalReq = coerceToRequest(argument) {
                let inject = shouldInject(for: originalReq)
                let instrumented = instrumentRequest(originalReq, sessionTaskId: sessionTaskId, injectHeaders: inject)
                // Use instrumented if available, else original
                return (instrumented ?? originalReq) as NSURLRequest
            }
            // Fallback: forward as-is
            return argument

        case .url:
            // Signature expects NSURL*
            // We cannot return a request here, so pre-log/inject via a temporary request if http(s)
            if let url = coerceToURL(argument) {
                if isHTTPScheme(url) {
                    let tempReq = URLRequest(url: url)
                    let inject = shouldInject(for: tempReq)
                    _ = instrumentRequest(tempReq, sessionTaskId: sessionTaskId, injectHeaders: inject)
                }
                return (url as NSURL)
            }
            // Fallback: forward as-is
            return argument

        case .resumeData:
            // Signature expects NSData*
            if let data = argument as? Data {
                return data as NSData
            }
            return argument

        case .unknown:
            return argument
        }
    }
    
    private func injectIntoNSURLSessionCreateTaskWithParameterMethods() {
        typealias UploadWithDataIMP = @convention(c) (URLSession, Selector, URLRequest, Data?) -> URLSessionTask
        typealias UploadWithFileIMP = @convention(c) (URLSession, Selector, URLRequest, URL) -> URLSessionTask
        
        let cls: AnyClass = URLSession.self
        
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
        let cls: AnyClass = URLSession.self
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
                
                if completionBlock != nil {
                    if objc_getAssociatedObject(argument, &idKey) == nil {
                        let completionWrapper: (Any?, URLResponse?, Error?) -> Void = { object, response, error in
                            if error != nil {
                                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                                #if DEBUG
                                Log.testLog("[URLSessionInstrumentation] Logging error for taskId: \(sessionTaskId), status: \(status)")
                                #endif
                                URLSessionLogger.logError(error!, dataOrFile: object, statusCode: status, instrumentation: self, sessionTaskId: sessionTaskId)
                            } else {
                                if let response = response {
                                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                                    #if DEBUG
                                    Log.testLog("[URLSessionInstrumentation] Logging response for taskId: \(sessionTaskId), status: \(status)")
                                    #endif
                                    URLSessionLogger.logResponse(response, dataOrFile: object, instrumentation: self, sessionTaskId: sessionTaskId)
                                }
                            }
                            // Mark as logged to prevent duplicate in setState: fallback
                            objc_setAssociatedObject(task, &Self.loggedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                            
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
                self.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
            originalIMP = method_setImplementation(original, swizzledIMP)
        }
    }
    
    private func injectIntoNSURLSessionAsyncUploadTaskMethods() {
        let cls: AnyClass = URLSession.self
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
            
            let block: @convention(block) (URLSession, URLRequest, AnyObject, ((Any?, URLResponse?, Error?) -> Void)?) -> URLSessionTask = { session, request, argument, completion in
                
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, URLRequest, AnyObject, ((Any?, URLResponse?, Error?) -> Void)?) -> URLSessionDataTask).self)
                
                var task: URLSessionTask!
                let sessionTaskId = UUID().uuidString
                
                var completionBlock = completion
                if objc_getAssociatedObject(argument, &idKey) == nil {
                    let completionWrapper: (Any?, URLResponse?, Error?) -> Void = { object, response, error in
                        if error != nil {
                            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                            #if DEBUG
                            Log.testLog("[URLSessionInstrumentation] Logging error for taskId: \(sessionTaskId), status: \(status)")
                            #endif
                            URLSessionLogger.logError(error!, dataOrFile: object, statusCode: status, instrumentation: self, sessionTaskId: sessionTaskId)
                        } else {
                            if let response = response {
                                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                                #if DEBUG
                                Log.testLog("[URLSessionInstrumentation] Logging response for taskId: \(sessionTaskId), status: \(status)")
                                #endif
                                URLSessionLogger.logResponse(response, dataOrFile: object, instrumentation: self, sessionTaskId: sessionTaskId)
                            }
                        }
                        // Mark as logged to prevent duplicate in setState: fallback
                        objc_setAssociatedObject(task, &Self.loggedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                        
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
                
                self.setIdKey(value: sessionTaskId, for: task)
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
        
        // Auto-detect and swizzle AFNetworking (if used) - no class scanning needed
        if let afManagerClass = NSClassFromString("AFURLSessionManager") {
            appendMethodIfExists(for: afManagerClass, selector: NSSelectorFromString("af_resume"))
            
            // Also check for AFHTTPSessionManager (subclass of AFURLSessionManager)
            if let afHTTPManagerClass = NSClassFromString("AFHTTPSessionManager") {
                appendMethodIfExists(for: afHTTPManagerClass, selector: NSSelectorFromString("af_resume"))
            }
        }
        
        for (cls, selector, method) in methodsToSwizzle {
            
            // ✅ Safety check: ensure method signature is void-return, no args
            // Accept variations like "v@:" or "v16@0:8" (with frame size info)
            guard let typeEncoding = method_getTypeEncoding(method) else {
                continue
            }
            let encoding = String(cString: typeEncoding)
            // Check if it's a void return method with no arguments (may include frame size info)
            guard encoding.starts(with: "v") && encoding.contains("@") && encoding.contains(":") else {
                continue
            }
            
            let originalIMP = method_getImplementation(method)
            
            let block: @convention(block) (AnyObject) -> Void = { [weak self] task in
                guard let self = self else { return }
                
                // Call hook
                if let urlSessionTask = task as? URLSessionTask {
                    #if DEBUG
                    Log.testLog("[URLSessionInstrumentation] 🔵 resume() called - task: \(urlSessionTask), URL: \(urlSessionTask.currentRequest?.url?.absoluteString ?? "nil")")
                    #endif
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
    
    // MARK: - Hybrid Approach: setState: Swizzling for Universal Coverage
    
    /// Discovers NSURLSessionTask classes to swizzle using a battle-tested approach (from AFNetworking)
    /// This is safe - creates a temporary session to discover the actual task class hierarchy
    /// without using objc_getClassList() which could trigger +initialize side effects
    private func discoverTaskClassesToSwizzle() -> [AnyClass] {
        // Create a temporary session with ephemeral configuration
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        
        // Create a dummy task to discover its actual class (use valid URL)
        guard let dummyURL = URL(string: "https://example.com") else { return [] }
        let dummyTask = session.dataTask(with: dummyURL)
        
        var currentClass: AnyClass? = type(of: dummyTask)
        var result: [AnyClass] = []
        
        let setStateSelector = NSSelectorFromString("setState:")
        
        #if DEBUG
        Log.testLog("[URLSessionInstrumentation] 🔍 Starting class discovery from: \(type(of: dummyTask))")
        #endif
        
        // Traverse the class hierarchy from the task's actual class up to NSObject
        // Collect all classes until we reach the base class or run out of hierarchy
        while let cls = currentClass {
            let className = NSStringFromClass(cls)
            
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] 🔍 Examining class: \(className)")
            #endif
            
            // Check if this class has setState: method
            if let method = class_getInstanceMethod(cls, setStateSelector) {
                #if DEBUG
                Log.testLog("[URLSessionInstrumentation] ✅ Class \(className) has setState: method")
                #endif
                
                // Get superclass to compare implementations
                if let superClass = class_getSuperclass(cls),
                   let superMethod = class_getInstanceMethod(superClass, setStateSelector) {
                    
                    let classIMP = method_getImplementation(method)
                    let superIMP = method_getImplementation(superMethod)
                    
                    // Only add if this class has its own implementation (not inherited)
                    if classIMP != superIMP {
                        result.append(cls)
                        #if DEBUG
                        Log.testLog("[URLSessionInstrumentation] ➕ Added \(className) - has unique implementation")
                        #endif
                    } else {
                        #if DEBUG
                        Log.testLog("[URLSessionInstrumentation] ⏭️ Skipped \(className) - inherited implementation")
                        #endif
                    }
                } else {
                    // This is the base class or can't find superclass method - add it and stop
                    result.append(cls)
                    #if DEBUG
                    Log.testLog("[URLSessionInstrumentation] ➕ Added \(className) - base class")
                    #endif
                    break
                }
            } else {
                #if DEBUG
                Log.testLog("[URLSessionInstrumentation] ⏹️ Class \(className) doesn't have setState:, stopping")
                #endif
                break
            }
            
            // Move up the hierarchy
            currentClass = class_getSuperclass(cls)
        }
        
        // Cleanup
        dummyTask.cancel()
        session.finishTasksAndInvalidate()
        
        #if DEBUG
        Log.testLog("[URLSessionInstrumentation] 🏁 Discovery complete: \(result.count) classes found")
        #endif
        
        return result
    }
    
    /// Swizzles setState: on discovered task classes for universal coverage (Alamofire, AFNetworking, etc.)
    /// This provides fallback logging when completion handlers or delegates don't fire
    private func injectIntoNSURLSessionTaskSetState() {
        let classesToSwizzle = discoverTaskClassesToSwizzle()
        
        #if DEBUG
        Log.testLog("[URLSessionInstrumentation] 🔍 Discovered \(classesToSwizzle.count) task classes for setState: swizzling: \(classesToSwizzle)")
        #endif
        
        guard !classesToSwizzle.isEmpty else {
            Log.w("[URLSessionInstrumentation] No task classes discovered for setState: swizzling")
            return
        }
        
        typealias SetStateIMPType = @convention(c) (AnyObject, Selector, URLSessionTask.State) -> Void
        let selector = NSSelectorFromString("setState:")
        
        for cls in classesToSwizzle {
            guard let method = class_getInstanceMethod(cls, selector) else {
                continue
            }
            
            // Check if already swizzled for this class
            if objc_getAssociatedObject(cls, &Self.setStateSwizzleKey) != nil {
                continue
            }
            
            let originalIMP = method_getImplementation(method)
            let instrumentation = self
            
            let block: @convention(block) (AnyObject, URLSessionTask.State) -> Void = { task, state in
                // Call original implementation first
                let originalFunc = unsafeBitCast(originalIMP, to: SetStateIMPType.self)
                originalFunc(task, selector, state)
                
                // Handle completion state for fallback logging
                if state == .completed, let urlTask = task as? URLSessionTask {
                    #if DEBUG
                    Log.testLog("[URLSessionInstrumentation] 🟢 setState: completed for task: \(urlTask)")
                    #endif
                    instrumentation.urlSessionTaskDidChangeState(urlTask, newState: state)
                }
            }
            
            let swizzledIMP = imp_implementationWithBlock(block as Any)
            method_setImplementation(method, swizzledIMP)
            
            // Mark as swizzled
            objc_setAssociatedObject(cls, &Self.setStateSwizzleKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] ✅ Swizzled setState: for class: \(cls)")
            #endif
        }
    }
    
    /// Called when task state changes to .completed - provides fallback logging for third-party libraries
    private func urlSessionTaskDidChangeState(_ task: URLSessionTask, newState: URLSessionTask.State) {
        guard newState == .completed else { return }
        
        #if DEBUG
        Log.testLog("[URLSessionInstrumentation] 🟣 setState: fired for task: \(task)")
        #endif
        
        // Check if already logged by completion handler or delegate
        if objc_getAssociatedObject(task, &Self.loggedKey) != nil {
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] ⏭️ Task already logged, skipping fallback")
            #endif
            return // Already logged, skip to avoid duplicates
        }
        
        // Fallback logging for tasks not captured by completion handlers or delegates
        // This handles Alamofire, AFNetworking, and other libraries
        logTaskCompletionFallback(task)
        
        // Mark as logged
        objc_setAssociatedObject(task, &Self.loggedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    /// Fallback logging method when completion handler or delegate didn't fire
    /// Provides basic instrumentation data (status, error, duration) without metrics or payload
    private func logTaskCompletionFallback(_ task: URLSessionTask) {
        #if DEBUG
        Log.testLog("[URLSessionInstrumentation] 🎯 logTaskCompletionFallback called for task: \(task)")
        #endif
        
        guard let taskId = objc_getAssociatedObject(task, &idKey) as? String else {
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] ❌ No taskId found - task not tracked")
            #endif
            return // Task not tracked by us
        }
        
        #if DEBUG
        Log.testLog("[URLSessionInstrumentation] ✅ Found taskId: \(taskId)")
        #endif
        
        var requestState: NetworkRequestState?
        queue.sync(flags: .barrier) {
            requestState = requestMap[taskId]
            if requestState != nil {
                requestMap[taskId] = nil
            }
        }
        
        // Log with basic data available from task
        if let error = task.error {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] Fallback logging error for taskId: \(taskId), status: \(status)")
            #endif
            URLSessionLogger.logError(error, dataOrFile: requestState?.dataProcessed, statusCode: status, instrumentation: self, sessionTaskId: taskId)
        } else if let response = task.response {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] Fallback logging response for taskId: \(taskId), status: \(status)")
            #endif
            URLSessionLogger.logResponse(response, dataOrFile: requestState?.dataProcessed, instrumentation: self, sessionTaskId: taskId)
        }
    }
    
    // MARK: - Delegate methods
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
        queue.async(flags: .barrier) {
            if (self.requestMap[taskId]?.request) != nil {
                self.createRequestState(for: taskId)
                if self.requestMap[taskId]?.dataProcessed == nil {
                    self.requestMap[taskId]?.dataProcessed = Data()
                }
                self.requestMap[taskId]?.dataProcessed?.append(dataCopy)
            }
        }
    }
    
    private func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard configuration.shouldRecordPayload?(session) ?? false else { return }
        guard let taskId = objc_getAssociatedObject(dataTask, &idKey) as? String else {
            return
        }
        queue.async(flags: .barrier) {
            if (self.requestMap[taskId]?.request) != nil {
                self.createRequestState(for: taskId)
                if response.expectedContentLength < 0 {
                    self.requestMap[taskId]?.dataProcessed = Data()
                } else {
                    self.requestMap[taskId]?.dataProcessed = Data(capacity: Int(response.expectedContentLength))
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskId = objc_getAssociatedObject(task, &idKey) as? String else {
            return
        }
    
        var requestState: NetworkRequestState?
        queue.sync(flags: .barrier) {
            requestState = requestMap[taskId]
            if requestState != nil {
                requestMap[taskId] = nil
            }
        }
        if let error = error {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] Logging error for taskId: \(taskId), status: \(status)")
            #endif
            URLSessionLogger.logError(error, dataOrFile: requestState?.dataProcessed, statusCode: status, instrumentation: self, sessionTaskId: taskId)
        } else if let response = task.response {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] Logging response for taskId: \(taskId), status: \(status)")
            #endif
            URLSessionLogger.logResponse(response, dataOrFile: requestState?.dataProcessed, instrumentation: self, sessionTaskId: taskId)
        }
        
        // Mark as logged to prevent duplicate in setState: fallback
        objc_setAssociatedObject(task, &Self.loggedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    private func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        guard let taskId = objc_getAssociatedObject(dataTask, &idKey) as? String else {
            return
        }
        setIdKey(value: taskId, for: downloadTask)
    }
    
    internal func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let taskId = objc_getAssociatedObject(task, &idKey) as? String else {
            return
        }
        var requestState: NetworkRequestState?
        queue.sync(flags: .barrier) {
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
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] Logging error for taskId: \(taskId), status: \(status)")
            #endif
            URLSessionLogger.logError(error, dataOrFile: requestState?.dataProcessed, statusCode: status, instrumentation: self, sessionTaskId: taskId)
        } else if let response = task.response {
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] Logging response for taskId: \(taskId), status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            #endif
            URLSessionLogger.logResponse(response, dataOrFile: requestState?.dataProcessed, instrumentation: self, sessionTaskId: taskId)
        }
        
        // Mark as logged to prevent duplicate in setState: fallback
        objc_setAssociatedObject(task, &Self.loggedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    private func urlSessionTaskWillResume(_ task: URLSessionTask) {
      // AV Asset Tasks cannot be auto instrumented, they dont include request attributes, skip them
      guard !Self.AVTaskClassList.contains(where: { task.isKind(of: $0) }) else {
        return
      }

      // We cannot instrument async background tasks because they crash if you assign a delegate
      if #available(OSX 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
        if objc_getAssociatedObject(task, "IsBackground") is Bool {
          guard Task.basePriority == nil else {
            return
          }
        }
      }

      let taskId = idKeyForTask(task)
      if let request = task.currentRequest {
        queue.sync(flags: .barrier) {
            if self.requestMap[taskId] == nil {
                self.requestMap[taskId] = NetworkRequestState()
          }
            self.requestMap[taskId]?.setRequest(request)
        }

        // Handle iOS 15+ async/await - try to inject headers via KVC
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
          // Try to detect if this is an async/await call
          var isAsyncContext = false
          
          if #available(OSX 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
            // iOS 16+: Use Task.basePriority as reliable indicator
            isAsyncContext = Task.basePriority != nil
          } else {
            // iOS 15: Heuristic - async tasks typically have no delegate
            let hasDelegate = task.delegate != nil
            let isRunning = task.state == .running
            let hasSessionDelegate = (task.value(forKey: "session") as? URLSession)?.delegate != nil
            isAsyncContext = !hasDelegate && !isRunning && !hasSessionDelegate
          }
          
          if isAsyncContext {
            #if DEBUG
            Log.testLog("[URLSessionInstrumentation] ✅ Detected async/await context, instrumenting request")
            #endif
            let instrumentedRequest = URLSessionLogger.processAndLogRequest(request,
                                                                            sessionTaskId: taskId,
                                                                            instrumentation: self,
                                                                            shouldInjectHeaders: true)
            if let instrumentedRequest {
              // Try to inject headers using KVC
              task.setValue(instrumentedRequest, forKey: "currentRequest")
            }
            self.setIdKey(value: taskId, for: task)

            // Set fake delegate if needed to capture completion
            if task.delegate == nil, task.state != .running, (task.value(forKey: "session") as? URLSession)?.delegate == nil {
              let fakeDelegate = FakeDelegate()
              fakeDelegate.instrumentation = self
              task.delegate = fakeDelegate
            }
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
    weak var instrumentation: URLSessionInstrumentation?
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Intentionally empty - we only care about metrics collection
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        #if DEBUG
        Log.testLog("[FakeDelegate] didFinishCollecting called, forwarding to instrumentation")
        #endif
        instrumentation?.urlSession(session, task: task, didFinishCollecting: metrics)
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
class AsyncTaskDelegate: NSObject, URLSessionTaskDelegate {
    private weak var instrumentation: URLSessionInstrumentation?
    private let sessionTaskId: String
    
    init(instrumentation: URLSessionInstrumentation, sessionTaskId: String) {
        self.instrumentation = instrumentation
        self.sessionTaskId = sessionTaskId
        super.init()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let instrumentation = instrumentation else {
            return
        }
        
        // Call the instrumentation's method to handle the completion
        // This ensures we go through the same logging path as other requests
        instrumentation.urlSession(session, task: task, didCompleteWithError: error)
    }
}
