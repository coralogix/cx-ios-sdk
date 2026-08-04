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
    private(set) var userId: String
    private(set) var userName: String
    private(set) var userEmail: String
    private(set) var userMetadata: [String: String]?
    var isPidEqualToOldPid: Bool = false
    var hasRecording: Bool = false
    // Whether the session this event belongs to was sampled in. false means the event
    // reached export only because its type is in excludeFromSampling. Read from the span
    // attribute stamped at creation time — never from the live flag, which may already
    // describe a newer session. Defaults to true: a span without the stamp (e.g. one
    // persisted by an older SDK version) can only reach export on a sampled-in session.
    var isSessionSampledIn: Bool = true

    init?(otel: SpanDataProtocol,
          userMetadata: [String: String]?,
          hasRecording: Bool = false) {
        guard let sessionInfo = SessionContext.resolveSession(from: otel) else {
            return nil  // Drop span if session attributes are missing
        }

        (self.sessionId, self.sessionCreationDate, self.isPidEqualToOldPid) = sessionInfo

        self.userId = otel.getString(forKey: .userId) ?? ""
        self.userName = otel.getString(forKey: .userName) ?? ""
        self.userEmail = otel.getString(forKey: .userEmail) ?? ""
        self.userMetadata = userMetadata
        self.hasRecording = hasRecording
        self.isSessionSampledIn = otel.getString(forKey: .spanSessionSampledIn).map { $0 == "true" } ?? true
    }
    
    private static func resolveSession(from otel: SpanDataProtocol) -> (id: String, creationDate: TimeInterval, isPidEqual: Bool)? {
        if shouldRestorePreviousSession(from: otel),
           let oldSessionId = otel.getString(forKey: .prevSessionId),
           let oldCreationDateString = otel.getString(forKey: .prevSessionCreationDate),
            let oldCreationDate = TimeInterval(oldCreationDateString) {
            return (oldSessionId, oldCreationDate, true)
        }
        
        // CRITICAL: Session attributes MUST be present on spans
        // If missing, this indicates a bug in instrumentation
        guard let sessionId = otel.getString(forKey: .sessionId) else {
            Log.w("[SessionContext] ⚠️  CRITICAL: Span missing sessionId attribute - dropping span to prevent data corruption")
            Log.w("[SessionContext]    Span name: \(otel.getName() ?? "unknown")")
            Log.w("[SessionContext]    This indicates a bug in the instrumentation that created this span")
            return nil
        }
        
        guard let timeIntervalString = otel.getString(forKey: .sessionCreationDate),
              let creationDate = TimeInterval(timeIntervalString) else {
            Log.w("[SessionContext] ⚠️  CRITICAL: Span missing sessionCreationDate attribute - dropping span to prevent data corruption")
            Log.w("[SessionContext]    Span name: \(otel.getName() ?? "unknown")")
            Log.w("[SessionContext]    Session ID: \(sessionId)")
            return nil
        }
        
        return (sessionId, creationDate, false)
    }
    
    /// Replaces the identity fields with the context a `PendingSnapshotTrigger` was
    /// armed with. The usual sources (span attributes stamped at creation, exporter
    /// options copied per span at encode) can predate the `setUserContext` call, and
    /// the promoted snapshot must reflect exactly the context that requested it.
    mutating func applyUserContextOverride(_ userContext: UserContext) {
        self.userId = userContext.userId
        self.userName = userContext.userName
        self.userEmail = userContext.userEmail
        self.userMetadata = userContext.userMetadata
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
        result[Keys.isSessionSampledIn.rawValue] = self.isSessionSampledIn
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
