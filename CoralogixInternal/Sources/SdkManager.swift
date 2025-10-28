//
//  SdkManager.swift
//
//
//  Created by Coralogix DEV TEAM on 09/01/2025.
//

import Foundation

public enum CaptureEventError: Error {
    case dummyInstance
    case sdkIdle
    case missingSessionReplayOptions
    case notRecording
    case skippingEvent
}

public protocol CoralogixInterface {
    func getSessionID() -> String
    func getCoralogixDomain() -> String
    func getPublicKey() -> String
    func getApplication() -> String
    func getSessionCreationTimestamp() -> TimeInterval
    func reportError(_ error: String)
    func isDebug() -> Bool
    func hasSessionRecording(_ hasSessionRecording: Bool)
    func periodicallyCaptureEventTriggered()
    func getProxyUrl() -> String
    func isIdle() -> Bool
}

public protocol SessionReplayInterface {
    func startRecording()
    func stopRecording()
    func captureEvent(properties: [String: Any]?) -> Result<Void, CaptureEventError>
    func update(sessionId: String)
}

public class SdkManager {
    public static let shared = SdkManager()
    
    private var coralogixSdk: CoralogixInterface?
    private var sessionReplaySdk: SessionReplayInterface?
    private let queue = DispatchQueue(label: Keys.queueSdkManager.rawValue)

    private init() {}

    // Register SDKs
    public func register(coralogixInterface: CoralogixInterface?) {
        queue.sync { self.coralogixSdk = coralogixInterface }
    }

    public func register(sessionReplayInterface: SessionReplayInterface?) {
        queue.sync { self.sessionReplaySdk = sessionReplayInterface }
    }

    // Access SDKs
    public func getCoralogixSdk() -> CoralogixInterface? {
        return queue.sync { coralogixSdk }
    }

    public func getSessionReplay() -> SessionReplayInterface? {
        return queue.sync { sessionReplaySdk }
    }
}
