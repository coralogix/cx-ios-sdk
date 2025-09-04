//
//  CoralogixExporter.swift
//
//  Created by Coralogix DEV TEAM on 27/03/2024.
//

import Foundation
import CoralogixInternal

public class CoralogixExporter: SpanExporter {
    private var options: CoralogixExporterOptions
    private var viewManager: ViewManager
    private var sessionManager: SessionManager
    private var networkManager: NetworkProtocol
    private var metricsManager: MetricsManager
    private var screenshotManager = ScreenshotManager()
    lazy var spanUploader = SpanUploader(options: self.options)

    private let spanProcessingQueue = DispatchQueue(label: Keys.queueSpanProcessingQueue.rawValue)
    
    public init(options: CoralogixExporterOptions,
                sessionManager: SessionManager,
                networkManager: NetworkProtocol,
                viewManager: ViewManager,
                metricsManager: MetricsManager) {
        self.options = options
        self.sessionManager = sessionManager
        self.networkManager = networkManager
        self.viewManager = viewManager
        self.metricsManager = metricsManager
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleNotification(notification:)),
                                               name: .cxRumNotificationSessionEnded, object: nil)
    }
    
    var pendingSpans: [SpanData] = []
    var endPoint: String {
      return "\(self.options.coralogixDomain.rawValue)\(Global.coralogixPath.rawValue)"
    }
    
    public func getOptions() -> CoralogixExporterOptions {
        return self.options
    }
    
    public func getViewManager() -> ViewManager {
        return self.viewManager
    }
    
    public func getScreenshotManager() -> ScreenshotManager {
        return self.screenshotManager
    }
    
    public func getSessionManager() -> SessionManager {
        return self.sessionManager
    }
    
    public func set(cxView: CXView) {
        if cxView.state == .notifyOnAppear {
            self.viewManager.set(cxView: cxView)
        } else if cxView.state == .notifyOnDisappear {
            self.viewManager.set(cxView: nil)
        }
    }
    
    public func update(userContext: UserContext) {
        self.options.userContext = userContext
    }
    
    public func update(labels: [String: Any]) {
        self.options.labels = labels
    }
    
    public func update(view: ViewManager) {
        self.viewManager = view
    }
    
    public func update(application: String, version: String) {
        self.options.version = version
        self.options.application = application
    }
    
    internal func sendBeforeSendData(data: [[String: Any]]) {
        self.spanUploader.upload(data, endPoint: self.endPoint)
    }
    
    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        if self.sessionManager.isIdle {
            Log.d("[SDK] Skipping export, session is idle")
            return .success
        }
        
        // ignore Urls
        var filterSpans = spans.filter { self.shouldRemoveSpan(span: $0) }
        if filterSpans.isEmpty { return .failure }
        
        // ignore Error
        filterSpans = filterSpans.filter { self.shouldFilterIgnoreError(span: $0) }
        
        // Deduplicate using spanId as key
        let uniqueSpansDict = Dictionary(grouping: filterSpans, by: { $0.spanId })
        let uniqueSpans = uniqueSpansDict.compactMap { $0.value.first }

        if !uniqueSpans.isEmpty {
            let cxSpansDictionary = autoreleasepool {
                encodeSpans(spans: uniqueSpans)
            }
            if cxSpansDictionary.isEmpty {
                return .success
            }
            
            let sdk = CoralogixRum.mobileSDK.sdkFramework
            switch sdk {
            case .flutter, .reactNative:
                if let callback = self.options.beforeSendCallBack {
                    let clonedSpans = cxSpansDictionary.deepCopy()
                    callback(clonedSpans)
                    return .success
                }
            default:
                return spanUploader.upload(cxSpansDictionary, endPoint: self.endPoint)
            }
        }
        return .failure
    }

    public func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        return .success
    }
    
    public func shutdown(explicitTimeout: TimeInterval?) {
        self.sessionManager.shutdown()
        self.viewManager.shutdown()
    }
    
    func encodeSpans(spans: [SpanData]) -> [[String: Any]] {
        var encodedSpans: [[String: Any]] = []
        let group = DispatchGroup()
        group.enter()
        spanProcessingQueue.async(flags: .barrier) { [weak self] in
            defer { group.leave() }
            guard let self = self else { return }
            encodedSpans = spans.compactMap { span in
                do {
                    return try? self.spanDatatoCxSpan(otelSpan: span)
                } catch {
                    Log.e("❌ Failed to encode span \(span.name): \(error)")
                    return nil
                }
            }
        }
        group.wait()
        return encodedSpans
    }
    
    @objc func handleNotification(notification: Notification) {
        self.viewManager.reset()
        self.sessionManager.reset()
        self.screenshotManager.reset()
    }
    
    private func spanDatatoCxSpan(otelSpan: SpanData) -> [String: Any]? {
        guard otelSpan.spanId.isValid, !otelSpan.attributes.isEmpty else {
            Log.e("Invalid otelSpan: \(otelSpan)")
            return nil
        }
        
        let metatadata = VersionMetadata(appName: self.options.application,
                                         appVersion: self.options.version)
        return CxSpan(otel: otelSpan,
                      versionMetadata: metatadata,
                      sessionManager: self.sessionManager,
                      networkManager: self.networkManager,
                      viewManager: self.viewManager,
                      metricsManager: self.metricsManager,
                      userMetadata: self.options.userContext?.userMetadata,
                      beforeSend: self.options.beforeSend,
                      labels: self.options.labels).getDictionary()
    }
    
    private func isMatchesRegexPattern(string: String, regexs: [String]) -> Bool {
        // Iterate over the regex patterns
        for regex in regexs {
            do {
                let regex = try NSRegularExpression(pattern: regex, options: [.caseInsensitive])
                let range = NSRange(string.startIndex..., in: string)
                let matchFound = regex.firstMatch(in: string, options: [], range: range) != nil
                return matchFound
            } catch {
                Log.d("Invalid regex pattern: \(regex) — Error: \(error)")
                continue // Skip invalid regex instead of crashing
            }
        }
        
        // Return false if no regex matches the host
        return false
    }
    
    internal func shouldRemoveSpan(span: SpanDataProtocol) -> Bool {
        // if the closure returns true, the element stays in the result.
        let attributes = span.getAttributes()
        var urlString: String?
        
        if let attrValue = attributes?[SemanticAttributes.httpUrl.rawValue] as? AttributeValue {
            urlString = attrValue.description  // Or attrValue.stringValue if available
        } else if let rawString = attributes?[SemanticAttributes.httpUrl.rawValue] as? String {
            urlString = rawString
        }
        
        guard let url = urlString?.description else {
            return true
        }
        
        if !Global.containsMonitoredPath(url) {
            if let ignoreUrlsOrRejexs = self.options.ignoreUrls,
               !ignoreUrlsOrRejexs.isEmpty,
               ignoreUrlsOrRejexs.contains(url) {
                return false
            }
            
            if let ignoreUrlsOrRejexs = self.options.ignoreUrls,
               !ignoreUrlsOrRejexs.isEmpty {
                let isMatch = Global.isURLMatchesRegexPattern(string: url, regexs: ignoreUrlsOrRejexs)
                return !isMatch
            }
            return true
        }
        return false
    }
    
    internal func shouldFilterIgnoreError(span: SpanDataProtocol) -> Bool {
        // if the closure returns true, the element stays in the result.
        let attributes = span.getAttributes()
        var message: String?

        if let attrValue = attributes?[Keys.errorMessage.rawValue] as? AttributeValue {
            message = attrValue.description
        } else if let rawString = attributes?[Keys.errorMessage.rawValue] as? String {
            message = rawString
        }
        
        guard let message = message?.description else {
            return true
        }
        
        if let ignoreErrorsOrRejexs = self.options.ignoreErrors,
           !ignoreErrorsOrRejexs.isEmpty,
           ignoreErrorsOrRejexs.contains(message) {
            return false
        }
        
        if let ignoreErrorsOrRejexs = self.options.ignoreErrors,
           !ignoreErrorsOrRejexs.isEmpty {
            let isMatch = self.isMatchesRegexPattern(string: message, regexs: ignoreErrorsOrRejexs)
            return !isMatch
        }
        
        return true
    }
}
