//
//  NetworkManager.swift
//
//
//  Created by Coralogix DEV TEAM on 14/01/2025.
//

import Foundation
import Coralogix_Internal

public class SRNetworkManager {
    public var endPoint: String?
    public var publicKey: String?
    public var application: String?
    public var sessionCreationTimestamp: TimeInterval?
    
    init() {
        guard let sdkManager = SdkManager.shared.getCoralogixSdk() else {
            Log.e("Failed to get CoralogixDomain")
            return
        }
        let coralogixDomain = sdkManager.getCoralogixDomain()
        self.endPoint = "\(coralogixDomain)\(Global.sessionReplayPath.rawValue)"
        self.publicKey = sdkManager.getPublicKey()
        self.application = sdkManager.getApplication()
        self.sessionCreationTimestamp = sdkManager.getSessionCreationTimestamp()
    }
    
    public func send(_ data: Data,
                     timestamp: TimeInterval,
                     sessionId: String,
                     trackNumber: Int,
                     subIndex: Int) -> SessionReplayResultCode {
        guard let endPoint = self.endPoint,
              let publicKey = self.publicKey,
              let sessionCreationTimestamp = self.sessionCreationTimestamp,
              let url = URL(string: endPoint) else { return .failure }
        var status: SessionReplayResultCode = .failure

        let metaData = encode(dataSize: data.count,
                              timestamp: timestamp,
                              sessionId: sessionId,
                              trackNumber: trackNumber,
                              subIndex: subIndex)
        
        // Convert the JSON to Data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: metaData, options: []) else {
            Log.e("[SRNetworkManager] Failed to convert JSON to Data")
            return .failure
        }
        
        // Boundary for separating parts
        let boundary = "Boundary-\(UUID().uuidString)"

        // Create the URLRequest
        var request = URLRequest(url: url)
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
    
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Log.e("[SRNetworkManager] Request failed with error: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Log.e("[SRNetworkManager] Invalid response")
                return
            }
            
            Log.d("[SRNetworkManager] Response status code: \(httpResponse.statusCode)")
            
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                Log.d("[SRNetworkManager] Response body: \(responseString)")
                status = .success
            }
        }
        task.resume()
        return status
    }
    
    private func encode(dataSize: Int,
                        timestamp: TimeInterval,
                        sessionId: String,
                        trackNumber: Int,
                        subIndex: Int) -> [String: Any] {
        guard let application = self.application else {
            Log.e("[SRNetworkManager] Session Replay missing Application name")
            return [String: Any]()
        }
        
        guard let sessionCreationTime = self.sessionCreationTimestamp else {
            Log.e("[SRNetworkManager] Session Replay missing Session Creation Time")
            return [String: Any]()
        }
        
        let metaData = [Keys.application.rawValue: application,
                        Keys.segmentIndex.rawValue: trackNumber,
                        Keys.segmentSize.rawValue: dataSize,
                        Keys.segmentTimestamp.rawValue: timestamp.milliseconds,
                        Keys.keySessionCreationDate.rawValue: sessionCreationTime.milliseconds,
                        Keys.keySessionId.rawValue: sessionId,
                        Keys.subIndex.rawValue: subIndex] as [String : Any]
        return metaData
    }
}
