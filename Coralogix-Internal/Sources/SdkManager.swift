//
//  SdkManager.swift
//
//
//  Created by Tomer Har Yoffi on 09/01/2025.
//

import Foundation

public protocol CoralogixInterface {
    func getSessionID() -> String
    func reportError(_ error: String)
}

public protocol SessionReplayInterface {
    func startRecording()
    func stopRecording()
    func captureEvent(name: String, properties: [String: Any])
}

public class SdkManager {
    public static let shared = SdkManager()
    
    private var coralogixSdk: CoralogixInterface?
    private var sessionReplaySdk: SessionReplayInterface?

    private init() {}

    // Register SDKs
    public func register(coralogixInterface: CoralogixInterface) {
        self.coralogixSdk = coralogixInterface
    }

    public func register(sessionReplayInterface: SessionReplayInterface) {
        self.sessionReplaySdk = sessionReplayInterface
    }

    // Access SDKs
    public func getCoralogixSdk() -> CoralogixInterface? {
        return coralogixSdk
    }

    public func getSessionReplay() -> SessionReplayInterface? {
        return sessionReplaySdk
    }
}
