//
//  NetworkRequestSampling.swift
//
//  Created by Coralogix DEV TEAM on 29/10/2026.
//

import Foundation

/// The `traceparent` sampled flag for a network request a hybrid wrapper sends itself, and the session
/// it was decided for. Returned by `CoralogixRum.networkRequestSampling()`; both values go back with the
/// report as `traceparentSampled` and `traceparentSessionId`.
public struct NetworkRequestSampling: Equatable {
    /// The flag to send: `true` → `01`, `false` → `00`.
    public let isSampled: Bool
    /// The session the decision belongs to; `nil` before the SDK is initialized.
    public let sessionId: String?

    public init(isSampled: Bool, sessionId: String?) {
        self.isSampled = isSampled
        self.sessionId = sessionId
    }
}
