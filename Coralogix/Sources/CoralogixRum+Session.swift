//
//  CoralogixRum+Session.swift
//
//
//  Created by Coralogix DEV TEAM on 03/11/2024.
//

import Foundation

extension CoralogixRum {
    public func isDebug() -> Bool {
        return self.options?.debug ?? false
    }

    public func getSessionCreationTimestamp() -> TimeInterval {
        return self.sessionManager?.getSessionMetadata()?.sessionCreationDate ?? 0
    }

    public func getApplication() -> String {
        return self.options?.application ?? ""
    }

    public func getCoralogixDomain() -> String {
        return self.options?.coralogixDomain.rawValue ?? ""
    }

    public func getProxyUrl() -> String {
        return self.options?.proxyUrl ?? ""
    }

    public func getPublicKey() -> String {
        return self.options?.publicKey ?? ""
    }

    public func getSessionID() -> String {
        return self.sessionManager?.getSessionMetadata()?.sessionId ?? ""
    }

    public func isIdle() -> Bool {
        return self.coralogixExporter?.getSessionManager().isIdle ?? false
    }

    public func isSessionSampledIn() -> Bool {
        return self.sessionManager?.isSessionSampledIn ?? false
    }
}
