//
//  SpanUploader.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 30/07/2025.
//

import Foundation
import CoralogixInternal

final class SpanUploader {
    private let options: CoralogixExporterOptions
    
    init(options: CoralogixExporterOptions) {
        self.options = options
    }
    
    @discardableResult
    func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
        guard CoralogixRum.isInitialized,
              let urlString = self.resolvedUrlString(endPoint: endPoint),
              let url = URL(string: urlString) else {
            return .failure
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = min(TimeInterval.greatestFiniteMagnitude, 10)
        request.httpMethod = "POST"
        request.addValue("Bearer \(self.options.publicKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonObject: [String: Any] = [
            Keys.logs.rawValue: spans,
            Keys.skipEnrichmentWithIp.rawValue: !options.collectIPData
        ]

        var requestJsonData: Data?
        do {
            requestJsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            request.httpBody = requestJsonData
        } catch {
            Log.e(error)
            return .failure
        }

        var status: SpanExporterResultCode = .failure
        let semaphore = DispatchSemaphore(value: 0)
        let jsonDataCopy = requestJsonData
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            defer { semaphore.signal() }
            
            if error != nil {
                status = .failure
                return
            }
            
            status = .success
            
            if let data = jsonDataCopy {
                self?.logJSON(from: data, prettyPrint: false)
            }
        }

        task.resume()
        semaphore.wait()
        return status
    }
    
    internal func resolvedUrlString(endPoint: String) -> String? {
        if let proxyUrl = self.options.proxyUrl,
            var urlComponents = URLComponents(string: proxyUrl) {
            urlComponents.queryItems = [
                URLQueryItem(name: Keys.cxforward.rawValue, value: endPoint)
            ]
            return urlComponents.url?.absoluteString
        } else {
            return endPoint
        }
    }
    
    internal func logJSON(from jsonData: Data, prettyPrint: Bool) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) else {
            return
        }
        
        let options: JSONSerialization.WritingOptions = prettyPrint ? .prettyPrinted : []
        
        if let formattedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: options),
           let jsonString = String(data: formattedData, encoding: .utf8) {
            Log.d("📤 Sending to Coralogix:\n\(jsonString)")
        }
    }
}
