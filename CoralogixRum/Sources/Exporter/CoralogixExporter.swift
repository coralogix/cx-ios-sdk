//
//  CoralogixExporter.swift
//
//  Created by Coralogix DEV TEAM on 27/03/2024.
//

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi

public class CoralogixExporter: SpanExporter {
    private var options: CoralogixExporterOptions
    private var versionMetadata: VersionMetadata
    private var viewManager: ViewManager
    private var sessionManager: SessionManager
    private var networkManager: NetworkProtocol

    public init(options: CoralogixExporterOptions,
                versionMetadata: VersionMetadata,
                sessionManager: SessionManager,
                networkManager: NetworkProtocol) {
        self.options = options
        self.versionMetadata = versionMetadata
        self.sessionManager = sessionManager
        self.networkManager = networkManager
        self.viewManager = ViewManager(keyChain: KeychainManager())
    }

    var pendingSpans: [SpanData] = []
    var endPoint: String {
        if let customDomainUrl = self.options.customDomainUrl {
            return "\(customDomainUrl)\(Global.coralogixPath.rawValue)"
        } else {
            return "\(self.options.coralogixDomain.rawValue)\(Global.coralogixPath.rawValue)"
        }
    }
    
    public func getOptions() -> CoralogixExporterOptions {
        return self.options
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
    
    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> OpenTelemetrySdk.SpanExporterResultCode {
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
            self.shouldFilterIgnoreUrl(span: $0)
        }
        
        // ignore Error
        filterSpans = filterSpans.filter {
            self.shouldFilterIgnoreError(span: $0)
        }
        
        var status: SpanExporterResultCode = .failure

        if !filterSpans.isEmpty {
            let cxSpansDictionary = encodeSpans(spans: filterSpans)
            let logs = [Keys.logs.rawValue: cxSpansDictionary]
            
            do {
                // Convert the dictionary to JSON data
                let jsonData = try JSONSerialization.data(withJSONObject: logs, options: [])
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
    
    public func flush(explicitTimeout: TimeInterval?) -> OpenTelemetrySdk.SpanExporterResultCode {
        return .success
    }
   
    public func shutdown(explicitTimeout: TimeInterval?) {
        self.sessionManager.shutdown()
    }
    
    func encodeSpans(spans: [SpanData]) -> [[String: Any]] {
        return spans.map { self.spanDatatoCxSpan(otelSpan: $0) }
    }
    
    private func spanDatatoCxSpan(otelSpan: SpanData) -> [String: Any] {
        return CxSpan(otel: otelSpan,
                      versionMetadata: self.versionMetadata,
                      sessionManager: self.sessionManager,
                      networkManager: self.networkManager, 
                      viewManager: self.viewManager,
                      userMetadata: self.options.userContext?.userMetadata,
                      labels: self.options.labels).getDictionary()
    }
    
    private func isMatchesRegexPattern(string: String, regexs: [String]) -> Bool {
        for regex in regexs {
            let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
            // Check if the URL matches the regular expression
            return predicate.evaluate(with: string) ? true : false
        }
        return false
    }
    
    private func shouldFilterIgnoreUrl(span: SpanData) -> Bool {
        guard let url = span.attributes[SemanticAttributes.httpUrl.rawValue]?.description else {
            return true
        }
                
        if url != self.endPoint {
            guard let ignoreUrlsOrRejexs = self.options.ignoreUrls else {
                return true
            }
            
            if ignoreUrlsOrRejexs.contains(url) {
                return false
            }
            
            return self.isMatchesRegexPattern(string: url, regexs: ignoreUrlsOrRejexs) ? false : true
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
