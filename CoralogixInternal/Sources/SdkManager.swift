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
    
    /// Reverts the screenshot counter when a capture is skipped, without checking which slot is
    /// being returned. Unused — every capture path knows its own reservation.
    @available(*, deprecated, message: "Use revertScreenshotCounter(page:segmentIndex:).")
    func revertScreenshotCounter()

    /// Returns the reservation a capture was given, identified by page and segment index.
    /// Only the most recent reservation can be returned, so this is a no-op when a newer
    /// capture has already taken an index — rolling back blindly would reissue that index and
    /// overwrite a frame that already shipped.
    func revertScreenshotCounter(page: Int, segmentIndex: Int)

    /// Emits the one-shot session-replay init log carrying the SessionReplayOptions snapshot.
    /// SessionReplay builds the snapshot (it owns the options type) and passes it as a dictionary,
    /// since the Coralogix module can't reference SessionReplayOptions.
    func reportSessionReplayInit(snapshot: [String: Any])
}

/// Outcome of a capture, delivered once the frame is either encoded or dropped.
public typealias CaptureEventCompletion = (Result<Void, CaptureEventError>) -> Void

public protocol SessionReplayInterface {
    func startRecording()
    func stopRecording()
    /// Immediate outcome only. Both capture paths finish after this returns — the native one
    /// encodes off-main, the Flutter one waits on Dart — so `.success` here means "the capture
    /// started", not "a frame shipped". Kept for hybrid bridges that have no span to stamp.
    func captureEvent(properties: [String: Any]?) -> Result<Void, CaptureEventError>
    /// Reports whether a frame was captured. `completion` fires exactly once. Callers that
    /// attach `screenshotId`/`page` to a span must use this one: on `.failure(.skippingEvent)`
    /// the screenshot index has been handed back and no frame will ever carry it.
    ///
    /// `.success` means the frame was encoded and queued for upload, not that the backend has
    /// it — delivery is retried out of band, long after a span has to close. So it answers
    /// "is there a frame for this index", which is the question a screenshot attribute asks.
    func captureEvent(properties: [String: Any]?, completion: @escaping CaptureEventCompletion)
    func update(sessionId: String)
    func isRecording() -> Bool
    func isInitialized() -> Bool
    func getSessionReplayFolderPath() -> String?
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
