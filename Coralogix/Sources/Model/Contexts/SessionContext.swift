//
//  SessionContext.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import CoralogixInternal

struct SessionContext {
    var sessionId: String
    var sessionCreationDate: TimeInterval
    let userId: String
    let userName: String
    let userEmail: String
    let userMetadata: [String: String]?
    var isPidEqualToOldPid: Bool = false
    var hasRecording: Bool = false
    
    init(otel: SpanDataProtocol,
         userMetadata: [String: String]?,
         hasRecording: Bool = false) {
        (self.sessionId, self.sessionCreationDate, self.isPidEqualToOldPid) = SessionContext.resolveSession(from: otel)

        self.userId = otel.getString(forKey: .userId) ?? ""
        self.userName = otel.getString(forKey: .userName) ?? ""
        self.userEmail = otel.getString(forKey: .userEmail) ?? ""
        self.userMetadata = userMetadata
        self.hasRecording = hasRecording
    }
    
    private static func resolveSession(from otel: SpanDataProtocol) -> (id: String, creationDate: TimeInterval, isPidEqual: Bool) {
        if shouldRestorePreviousSession(from: otel),
           let oldSessionId = otel.getString(forKey: .prevSessionId),
           let oldCreationDateString = otel.getString(forKey: .prevSessionCreationDate),
            let oldCreationDate = TimeInterval(oldCreationDateString) {
            return (oldSessionId, oldCreationDate, true)
        }
        
        let sessionId = otel.getString(forKey: .sessionId) ?? UUID().uuidString.lowercased()
        var creationDate: TimeInterval = Date().timeIntervalSince1970
        if let timeIntervalString = otel.getString(forKey: .sessionCreationDate),
           let timeInterval = TimeInterval(timeIntervalString) {
            creationDate = timeInterval
        }
        return (sessionId, creationDate, false)
    }
    
    static func shouldRestorePreviousSession(from otel: SpanDataProtocol) -> Bool {
        guard let pid = otel.getString(forKey: .pid),
              let oldPid = otel.getString(forKey: .prevPid) else {
            return false
        }
        return pid == oldPid
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        
        result[Keys.sessionId.rawValue] = self.sessionId
        result[Keys.sessionCreationDate.rawValue] = self.sessionCreationDate.milliseconds
        result[Keys.userId.rawValue] = self.userId
        result[Keys.userName.rawValue] = self.userName
        result[Keys.userEmail.rawValue] = self.userEmail
        result[Keys.hasRecording.rawValue] = self.hasRecording
        if let userMetadata = self.userMetadata {
            result[Keys.userMetadata.rawValue] = userMetadata
        }
        return result
    }
    
    func getPrevSessionDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.sessionId.rawValue] = self.sessionId
        result[Keys.sessionCreationDate.rawValue] = self.sessionCreationDate.milliseconds
        return result
    }
}


// MARK: - Helper Extension

private extension SpanDataProtocol {
    func getString(forKey key: Keys) -> String? {
        getAttribute(forKey: key.rawValue) as? String
    }
    
    func getTimeInterval(forKey key: Keys) -> TimeInterval? {
        getAttribute(forKey: key.rawValue) as? TimeInterval
    }
}
