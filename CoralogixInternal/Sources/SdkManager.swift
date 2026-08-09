//
//  SdkManager.swift
//
//
//  Created by Coralogix DEV TEAM on 09/01/2025.
//

import Foundation
import CoreGraphics

public enum CaptureEventError: Error {
    case dummyInstance
    case sdkIdle
    case missingSessionReplayOptions
    case notRecording
    case skippingEvent
    case invalidSessionId
    case captureFailed
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
    
    /// Returns the next screenshot location properties (segmentIndex, page, screenshotId).
    /// Used by SessionReplay when captureEvent is called without properties.
    func getNextScreenshotLocationProperties() -> [String: Any]
    
    /// Reverts the screenshot counter when a capture is skipped.
    func revertScreenshotCounter()

    /// Emits the one-shot session-replay init log carrying the SessionReplayOptions snapshot.
    /// SessionReplay builds the snapshot (it owns the options type) and passes it as a dictionary,
    /// since the Coralogix module can't reference SessionReplayOptions.
    func reportSessionReplayInit(snapshot: [String: Any])
}

public protocol SessionReplayInterface {
    func startRecording()
    func stopRecording()
    func captureEvent(properties: [String: Any]?) -> Result<Void, CaptureEventError>
    func update(sessionId: String)
    func isRecording() -> Bool
    func isInitialized() -> Bool
    func getSessionReplayFolderPath() -> String?

    /// The mask rectangles (screen coordinates, points) a frame captured at this moment would
    /// paint for native content — the same families the capture pass collects (`cxMask`,
    /// `maskText`, `maskAllImages`, navigation-bar titles). The interaction path tests a tap
    /// against these so `is_masked_element` and inner-text redaction resolve from the same
    /// geometry that suppresses the replay's tap marker, and the metadata cannot contradict
    /// the pixels. Returns nil when unresolvable (off the main thread, or no options) — the
    /// caller must treat nil as "unknown", never as "unmasked geometry exists".
    func currentMaskRects() -> [CGRect]?
}

public extension SessionReplayInterface {
    /// Default for conformers that predate mask-geometry reporting: nil = "unknown", so the
    /// interaction path falls back to its other oracles rather than reading "nothing masked".
    /// Keeps existing conformers source-compatible; SessionReplay overrides with real rects.
    func currentMaskRects() -> [CGRect]? { nil }
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
