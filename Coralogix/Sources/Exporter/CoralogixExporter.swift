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
      return "\(self.options.coralogixDomain.rawValue)\(Global.coralogixPath.rawValue)"
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

        // Deduplicate using spanId as key
        let uniqueSpansDict = Dictionary(grouping: filterSpans, by: { $0.spanId })
        let uniqueSpans = uniqueSpansDict.compactMap { $0.value.first }

        if !uniqueSpans.isEmpty {
            let cxSpansDictionary = encodeSpans(spans: uniqueSpans)
            
            if cxSpansDictionary.isEmpty {
                return .success
            }
            
            let jsonObject = [Keys.logs.rawValue: cxSpansDictionary, Keys.skipEnrichmentWithIp.rawValue: !options.collectIPData] as [String: Any]
            
            do {
                // Convert the dictionary to JSON data
                let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
                request.httpBody = jsonData
                
                self.logJSON(from: jsonData, prettyPrint: false)
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
    
    private func logJSON(from jsonData: Data, prettyPrint: Bool) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) else {
            Log.d("❌ Failed to parse JSON data.")
            return
        }
        
        let options: JSONSerialization.WritingOptions = prettyPrint ? .prettyPrinted : []
        
        if let formattedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: options),
           let jsonString = String(data: formattedData, encoding: .utf8) {
            Log.d("⚡️ JSON string: ⚡️\n\(jsonString)")
        } else {
            Log.d("❌ Failed to format JSON string.")
        }
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
    
    private func isHostMatchesRegexPattern(string: String, regexs: [String]) -> Bool {
        guard let url = URL(string: string), let host = url.host else {
            return false // Return false if URL creation fails or no host part exists
        }
        
        // Iterate over the regex patterns
        for regex in regexs {
            do {
                let regex = try NSRegularExpression(pattern: regex)
                let range = NSRange(location: 0, length: host.utf16.count)
                if regex.firstMatch(in: host, options: [], range: range) != nil {
                    return true
                }
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
        
        if url != self.endPoint {
            if let ignoreUrlsOrRejexs = self.options.ignoreUrls,
               !ignoreUrlsOrRejexs.isEmpty,
               ignoreUrlsOrRejexs.contains(url)  {
                return false
            }
            
            if let ignoreUrlsOrRejexs = self.options.ignoreUrls,
               !ignoreUrlsOrRejexs.isEmpty {
                let isMatch = self.isHostMatchesRegexPattern(string: url, regexs: ignoreUrlsOrRejexs)
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
