//
//  NetworkManager.swift
//
//
//  Created by Tomer Har Yoffi on 14/01/2025.
//

import Foundation
import Coralogix_Internal

public class SRNetworkManager {
    public var endPoint: String?
    public var publicKey: String?
    public var application: String?
    
    init() {
        guard let sdkManager = SdkManager.shared.getCoralogixSdk() else {
            Log.e("Failed to get CoralogixDomain")
            return
        }
        let coralogixDomain = sdkManager.getCoralogixDomain()
        self.endPoint = "\(coralogixDomain)\(Global.sessionReplayPath.rawValue)"
        self.publicKey = sdkManager.getPublicKey()
        self.application = sdkManager.getApplication()
    }
    
    public func send(_ data: Data,
                     timestamp: TimeInterval,
                     sessionId: String,
                     trackNumber: Int) -> SessionReplayResultCode {
        guard let endPoint = self.endPoint,
              let publicKey = self.publicKey,
              let url = URL(string: endPoint) else { return .failure }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = min(TimeInterval.greatestFiniteMagnitude, 10)
        request.httpMethod = "POST"
        request.addValue("Bearer \(publicKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var status: SessionReplayResultCode = .failure
        let jsonObject = encode(data: data,
                                timestamp: timestamp,
                                sessionId: sessionId,
                                trackNumber: trackNumber)
        
        if jsonObject.isEmpty {
            return .success
        }
        
        do {
            // Convert the dictionary to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            request.httpBody = jsonData
            
            // Convert JSON data to a string if needed
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Log.d("⚡️ Session Replay string: ⚡️\n\(jsonString)")
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
        
        return status
    }
    
    private func encode(data: Data,
                        timestamp: TimeInterval,
                        sessionId: String,
                        trackNumber: Int) -> [String: Any] {
        guard let application = self.application else {
            Log.e("Session Replay missing Application name")
            return [String: Any]()
        }
        
        let events = ["base64", "base64"]
        let metaData = [Keys.application.rawValue: application,
                        Keys.segmentIndex.rawValue: trackNumber,
                        Keys.segmentSize.rawValue: data.count,
                        Keys.segmentTimestamp.rawValue: timestamp,
                        Keys.sessionCreationTime.rawValue: "Timestamp",
                        Keys.keySessionId.rawValue: sessionId,
                        Keys.subIndex.rawValue: -1] as [String : Any]
        var paylod = [Keys.metadata.rawValue: metaData,
                      Keys.events.rawValue: events] as [String : Any]
        return paylod
    }
}
