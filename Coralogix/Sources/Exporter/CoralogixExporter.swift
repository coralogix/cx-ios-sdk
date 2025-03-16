//
//  CoralogixExporter.swift
//
//  Created by Coralogix DEV TEAM on 27/03/2024.
//

import Foundation

public class CoralogixExporter: SpanExporter {
    private var options: CoralogixExporterOptions
    private var viewManager: ViewManager
    private var sessionManager: SessionManager
    private var networkManager: NetworkProtocol
    private var metricsManager: MetricsManager
    
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
        if let customDomainUrl = self.options.customDomainUrl,
           self.options.customDomainUrl != "" {
            return "\(customDomainUrl)\(Global.coralogixPath.rawValue)"
        } else {
            return "\(self.options.coralogixDomain.rawValue)\(Global.coralogixPath.rawValue)"
        }
    }
    
    public func getOptions() -> CoralogixExporterOptions {
        return self.options
    }
    
    public func getViewManager() -> ViewManager {
        return self.viewManager
    }
    
    public func set(cxView: CXView) {
        if cxView.state == .notifyOnAppear {
            self.viewManager.set(cxView: cxView)
        } else if cxView.state == .notifyOnDisappear {
            self.viewManager.set(cxView: nil)
        }
    }
    
    public func updade(userContext: UserContext) {
        self.options.userContext = userContext
    }
    
    public func updade(labels: [String: Any]) {
        self.options.labels = labels
    }
    
    public func updade(view: ViewManager) {
        self.viewManager = view
    }
    
    public func updade(application: String, version: String) {
        self.options.version = version
        self.options.application = application
    }
    
    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        guard CoralogixRum.isInitialized,
              let url = URL(string: self.endPoint) else { return .failure }
        self.sessionManager.updateActivityTime()
        var request = URLRequest(url: url)
        request.timeoutInterval = min(TimeInterval.greatestFiniteMagnitude, 10)
        request.httpMethod = "POST"
        request.addValue("Bearer \(self.options.publicKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // ignore Urls
        var filterSpans = spans.filter {
            self.shouldRemoveSpan(span: $0)
        }
        
        // ignore Error
        filterSpans = filterSpans.filter {
            self.shouldFilterIgnoreError(span: $0)
        }
        
        var status: SpanExporterResultCode = .failure
        
        if !filterSpans.isEmpty {
            let cxSpansDictionary = encodeSpans(spans: filterSpans)
            
            if cxSpansDictionary.isEmpty {
                return .success
            }
            
            let jsonObject = [Keys.logs.rawValue: cxSpansDictionary, Keys.skipEnrichmentWithIp.rawValue: !options.collectIPData] as [String: Any]
            
            do {
                // Convert the dictionary to JSON data
                let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
                request.httpBody = jsonData
                
                // Convert JSON data to a string if needed
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    Log.d("⚡️ JSON string: ⚡️\n\(jsonString)")
                }
            } catch {
                Log.e(error)
                return .failure
            }
            
            let task = URLSession.shared.dataTask(with: request) { _, _, error in
                if error != nil {
                    status = .failure
                } else {
                    status = .success
                }
            }
            task.resume()
        }
        return status
    }
    
    public func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        return .success
    }
    
    public func shutdown(explicitTimeout: TimeInterval?) {
        self.sessionManager.shutdown()
        self.viewManager.shutdown()
    }
    
    func encodeSpans(spans: [SpanData]) -> [[String: Any]] {
        return spans.compactMap { self.spanDatatoCxSpan(otelSpan: $0) }
    }
    
    @objc func handleNotification(notification: Notification) {
        self.viewManager.reset()
        self.sessionManager.reset()
    }
    
    private func spanDatatoCxSpan(otelSpan: SpanData) -> [String: Any]? {
        let metatadata = VersionMetadata(appName: self.options.application, appVersion: self.options.version)
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
        guard let url = URL(string: string), let host = url.host else {
            return false // Return false if URL creation fails or no host part exists
        }
        
        // Iterate over the regex patterns
        for regex in regexs {
            let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
            // Check if the domain part (host) matches the regex
            if predicate.evaluate(with: host) {
                return true
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
           return false
        }
        
        if url != self.endPoint {
            if let ignoreUrlsOrRejexs = self.options.ignoreUrls,
               !ignoreUrlsOrRejexs.isEmpty,
               ignoreUrlsOrRejexs.contains(url)  {
                return false
            }
            
            if let ignoreUrlsOrRejexs = self.options.ignoreUrls,
               !ignoreUrlsOrRejexs.isEmpty {
                let isMatch = self.isMatchesRegexPattern(string: url, regexs: ignoreUrlsOrRejexs) 
                return !isMatch
            }
            return true
        }
        return false
    }
    
    private func shouldFilterIgnoreError(span: SpanData) -> Bool {
        guard let message = span.attributes[Keys.message.rawValue]?.description else {
            return true
        }
        
        guard let ignoreErrorsOrRejexs = self.options.ignoreErrors else {
            return true
        }
        
        if ignoreErrorsOrRejexs.contains(message) {
            return false
        }
        
        return self.isMatchesRegexPattern(string: message, regexs: ignoreErrorsOrRejexs) ? false : true
    }
}
