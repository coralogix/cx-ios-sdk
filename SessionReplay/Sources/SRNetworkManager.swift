//
//  NetworkManager.swift
//
//
//  Created by Coralogix DEV TEAM on 14/01/2025.
//

import Foundation
import CoralogixInternal

protocol URLSessionDataTaskProtocol {
    func resume()
}

protocol URLSessionProtocol {
    func dataTask(with request: URLRequest,
                  completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTaskProtocol
}

extension URLSessionDataTask: URLSessionDataTaskProtocol {}

extension URLSession: URLSessionProtocol {
    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTaskProtocol {
        return dataTask(with: request, completionHandler: completionHandler) as URLSessionDataTask
    }
}

public class MetadataBuilder {
    public func buildMetadata(dataSize: Int,
                              timestamp: TimeInterval,
                              sessionId: String,
                              screenshotNumber: Int,
                              subIndex: Int,
                              application: String,
                              sessionCreationTime: TimeInterval,
                              screenshotId: String,
                              page: String) -> [String: Any] {
        return [
            Keys.application.rawValue: application,
            Keys.segmentIndex.rawValue: screenshotNumber,
            Keys.segmentSize.rawValue: dataSize,
            Keys.segmentTimestamp.rawValue: timestamp.milliseconds,
            Keys.keySessionCreationDate.rawValue: sessionCreationTime.milliseconds,
            Keys.keySessionId.rawValue: sessionId,
            Keys.subIndex.rawValue: subIndex,
            Keys.snapshotId.rawValue: screenshotId,
            Keys.page.rawValue: page,
        ]
    }
}

public class SRNetworkManager {
    public var endPoint: String?
    public var publicKey: String?
    public var application: String?
    public var sessionCreationTimestamp: TimeInterval?
    var session: URLSessionProtocol?
    private let metadataBuilder = MetadataBuilder()

    init(session: URLSessionProtocol = URLSession.shared) {
        guard let sdkManager = SdkManager.shared.getCoralogixSdk() else {
            Log.e("Failed to get CoralogixDomain")
            return
        }
        let coralogixDomain = sdkManager.getCoralogixDomain()
        self.endPoint = "\(coralogixDomain)\(Global.sessionReplayPath.rawValue)"
        self.publicKey = sdkManager.getPublicKey()
        self.application = sdkManager.getApplication()
        self.sessionCreationTimestamp = sdkManager.getSessionCreationTimestamp()
        self.session = session
    }
    
    public func send(_ data: Data,
                     timestamp: TimeInterval,
                     sessionId: String,
                     screenshotNumber: Int,
                     subIndex: Int,
                     screenshotId: String,
                     page: String,
                     completion: @escaping (SessionReplayResultCode) -> Void) {
        guard let endPoint = self.endPoint,
              let publicKey = self.publicKey,
              let url = URL(string: endPoint) else {
            completion(.failure)
            return
        }
        
        guard let session = self.session else {
            Log.e("[SRNetworkManager] URLSession not initialised – aborting send")
            completion(.failure)
            return
        }
        
        guard let application = self.application else {
            Log.e("[SRNetworkManager] Session Replay missing Application name")
            completion(.failure)
            return
        }
        
        guard let sessionCreationTime = self.sessionCreationTimestamp else {
            Log.e("[SRNetworkManager] Session Replay missing Session Creation Time")
            completion(.failure)
            return
        }
        
        let metadata = metadataBuilder.buildMetadata(
            dataSize: data.count,
            timestamp: timestamp,
            sessionId: sessionId,
            screenshotNumber: screenshotNumber,
            subIndex: subIndex,
            application: application,
            sessionCreationTime: sessionCreationTime,
            screenshotId: screenshotId,
            page: page
        )
        Log.d("[metadata] \(metadata)")
        
        // Convert the JSON to Data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: []) else {
            Log.e("[SRNetworkManager] Failed to convert JSON to Data")
            completion(.failure)
            return
        }
        
        // Boundary for separating parts
        let boundary = "Boundary-\(UUID().uuidString)"

        // Create the URLRequest
        var request = URLRequest(url: url)
        Log.d(String(describing: request))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(publicKey)", forHTTPHeaderField: "Authorization")
        
        // Create the request body
        var body = Data()
        
        // Add the JSON part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(Keys.metaData.rawValue)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(jsonData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add chunk (binary data)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chunk\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        
        // End the body with the boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Set the body to the request
        request.httpBody = body
    
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Log.e("[SRNetworkManager] Request failed with error: \(error.localizedDescription)")
                completion(.failure)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Log.e("[SRNetworkManager] Invalid response")
                completion(.failure)
                return
            }
            
            Log.w("[SRNetworkManager] Response status code: \(httpResponse.statusCode)")
            
            if let data = data,
               let responseString = String(data: data, encoding: .utf8) {
                Log.d("[SRNetworkManager] Response body: \(responseString)")
            }
            let successRange = 200..<300
            completion(successRange.contains(httpResponse.statusCode) ? .success: .failure)
        }
        task.resume()
    }
}
