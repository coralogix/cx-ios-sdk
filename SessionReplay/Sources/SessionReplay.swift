//
//  SessionReplay.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 03/11/2024.
//

import AVFoundation
import ReplayKit
import UIKit
import CoralogixInternal

/// Represents the configuration options for session replay functionality.
public struct SessionReplayOptions {
    public enum RecordingType {
        case image, video
    }
    /// The type of recording to be used during the session. image / video (TBD)
    public var recordingType: RecordingType

    /// The time interval (in seconds) between each capture.
    public var captureTimeInterval: TimeInterval

    /// The scale factor to apply to the captured images.
    public var captureScale: CGFloat

    /// The compression quality for the captured images (0.0 to 1.0).
    public var captureCompressionQuality: CGFloat

    /// The sampling rate for session recording events.
    public var sessionRecordingSampleRate: Int

    /// Text patterns to mask in the captured content. Each entry is either a plain literal
    /// string (case-insensitive substring match) or a regular expression. Use `[".*"]` to mask
    /// all text labels.
    public var maskText: [String]?

    /// Whether all images should be masked in the captured content.
    public var maskAllImages: Bool

    /// Whether Credit card images should be masked in the captured content. On / Off
    public var maskOnlyCreditCards: Bool

    /// Whether faces should be masked in the captured content.
    public var maskFaces: Bool

    /// Determines if an image may contain a credit card based on specific text patterns.
    public var creditCardPredicate: [String]?

    /// Automatically starts session recording if enabled in the options.
    public var autoStartSessionRecording: Bool

    /// When set, the SDK requests a pre-masked bitmap from this provider
    /// for each FlutterView found in the captured view hierarchy.
    ///
    /// The Flutter plugin registers this callback to return finished RGBA pixel data;
    /// the SDK substitutes it into the FlutterView region of the captured host bitmap.
    /// This path replaces the frame-skew-prone pull-based maskRegionsProvider.
    public var flutterViewBitmapProvider: FlutterViewBitmapProvider?

    public init(recordingType: RecordingType = .image,
                captureScale: CGFloat = 2.0,
                captureCompressionQuality: CGFloat = 1.0,
                sessionRecordingSampleRate: Int = 100,
                maskText: [String]? = nil,
                maskOnlyCreditCards: Bool = false,
                maskAllImages: Bool = true,
                maskFaces: Bool = false,
                creditCardPredicate: [String]? = nil,
                autoStartSessionRecording: Bool = false,
                flutterViewBitmapProvider: FlutterViewBitmapProvider? = nil) {
        self.recordingType = recordingType
        self.captureTimeInterval = 1.0
        self.captureScale = captureScale
        self.captureCompressionQuality = captureCompressionQuality
        self.maskText = maskText
        self.maskOnlyCreditCards = maskOnlyCreditCards
        self.maskFaces = maskFaces
        self.maskAllImages = maskAllImages
        self.creditCardPredicate = creditCardPredicate
        self.autoStartSessionRecording = autoStartSessionRecording
        self.sessionRecordingSampleRate = sessionRecordingSampleRate
        self.flutterViewBitmapProvider = flutterViewBitmapProvider
    }

    @available(*, deprecated, message: "captureTimeInterval is deprecated and will be removed in a future release. 1 fps (1.0 s interval) is the only supported capture rate. Values below 1.0 s may cause performance and masking issues; values above 1.0 s will result in lower capture fidelity. Construct SessionReplayOptions without this parameter to use the supported default.")
    public init(recordingType: RecordingType = .image,
                captureTimeInterval: TimeInterval,
                captureScale: CGFloat = 2.0,
                captureCompressionQuality: CGFloat = 1.0,
                sessionRecordingSampleRate: Int = 100,
                maskText: [String]? = nil,
                maskOnlyCreditCards: Bool = false,
                maskAllImages: Bool = true,
                maskFaces: Bool = false,
                creditCardPredicate: [String]? = nil,
                autoStartSessionRecording: Bool = false,
                flutterViewBitmapProvider: FlutterViewBitmapProvider? = nil) {
        self.recordingType = recordingType
        self.captureTimeInterval = captureTimeInterval
        self.captureScale = captureScale
        self.captureCompressionQuality = captureCompressionQuality
        self.maskText = maskText
        self.maskOnlyCreditCards = maskOnlyCreditCards
        self.maskFaces = maskFaces
        self.maskAllImages = maskAllImages
        self.creditCardPredicate = creditCardPredicate
        self.autoStartSessionRecording = autoStartSessionRecording
        self.sessionRecordingSampleRate = sessionRecordingSampleRate
        self.flutterViewBitmapProvider = flutterViewBitmapProvider
    }
}

/// Manages session replay functionality, including recording and event capture.
public class SessionReplay: SessionReplayInterface {

    private static var initializationAttempted = false
    var sessionReplayModel: SessionReplayModel?

    public static var shared: SessionReplay! {
        get {
            guard _shared != nil else {
                Log.e("SessionReplay.shared accessed before initialization. Call SessionReplay.initializeWithOptions first.")
                return createDummyInstance()
            }
            return _shared
        }
    }

    private static var _shared: SessionReplay?

    internal var sessionReplayOptions: SessionReplayOptions?
    internal var isDummyInstance = false

    private init(sessionReplayOptions: SessionReplayOptions) {
        self.sessionReplayOptions = sessionReplayOptions
        self.sessionReplayModel = SessionReplayModel(sessionReplayOptions: sessionReplayOptions)

        DispatchQueue.main.async {
            SdkManager.shared.register(sessionReplayInterface: self)
        }

        guard let coralogixSdk = SdkManager.shared.getCoralogixSdk() else {
            Log.e("[SessionReplay] CoralogixSdk is not initialized")
            return
        }

        let sessionId = coralogixSdk.getSessionID()
        self.update(sessionId: sessionId)

        if sessionReplayOptions.autoStartSessionRecording {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.startRecording()
            }
        }
    }

    public static func initializeWithOptions(sessionReplayOptions: SessionReplayOptions) {
        guard !initializationAttempted else {
            Log.e("SessionReplay initialization already attempted!")
            return
        }

        initializationAttempted = true

        guard SRUtils.shouldInitialize(sampleRate: sessionReplayOptions.sessionRecordingSampleRate) else {
            Log.d("SessionReplay initialization skipped due to sampling")
            _shared = createDummyInstance(sessionReplayOptions)
            return
        }

        _shared = SessionReplay(sessionReplayOptions: sessionReplayOptions)
    }

    internal static func createDummyInstance(_ options: SessionReplayOptions? = nil) -> SessionReplay {
        let instance = SessionReplay()
        instance.isDummyInstance = true
        instance.sessionReplayOptions = options
        return instance
    }

    private init() { }

    public func startRecording() {
        if isDummyInstance {
            Log.d("SessionReplay.startRecording() called on inactive instance (skipped by sampling)")
            return
        }

        guard let sessionReplayModel = self.sessionReplayModel,
              let sessionReplayOptions = sessionReplayModel.sessionReplayOptions else {
            Log.e("[SessionReplay] missing sessionReplayOptions")
            return
        }

        if sessionReplayOptions.recordingType == .image {
            guard !sessionReplayModel.isRecording else {
                Log.e("[SessionReplay] already recording")
                return
            }
            sessionReplayModel.isRecording = true

            guard let coralogixSdk = SdkManager.shared.getCoralogixSdk() else {
                Log.e("[SessionReplay] CoralogixSdk is not initialized")
                return
            }
            if coralogixSdk.isDebug(),
               let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let path = documentsDirectory.appendingPathComponent("SessionReplay").path
                Log.d("[SessionReplay] saving images to: \(path)")
            }
            coralogixSdk.periodicallyCaptureEventTriggered()
            sessionReplayModel.captureTimer = Timer.scheduledTimer(withTimeInterval: sessionReplayOptions.captureTimeInterval, repeats: true) { _ in
                coralogixSdk.periodicallyCaptureEventTriggered()
            }
        }
    }

    public func stopRecording() {
        if isDummyInstance {
            Log.d("SessionReplay.stopRecording() called on inactive instance (skipped by sampling)")
            return
        }

        guard let sessionReplayModel = self.sessionReplayModel,
              let sessionReplayOptions = sessionReplayModel.sessionReplayOptions else {
            Log.e("[SessionReplay] missing sessionReplayOptions")
            return
        }

        if sessionReplayOptions.recordingType == .image {
            sessionReplayModel.isRecording = false
            sessionReplayModel.captureTimer?.invalidate()
            sessionReplayModel.captureTimer = nil
        }
    }

    public func captureEvent(properties: [String : Any]?) -> Result<Void, CaptureEventError> {
        if isDummyInstance {
            Log.d("[SessionReplay] captureEvent() called on inactive instance (skipped by sampling)")
            return .failure(.dummyInstance)
        }

        guard let coralogixSdk = SdkManager.shared.getCoralogixSdk(),
              !coralogixSdk.isIdle() else {
            Log.d("[SessionReplay] CoralogixSdk is idle and skiped capture event")
            return .failure(.sdkIdle)
        }

        guard let sessionReplayModel = self.sessionReplayModel,
              let sessionReplayOptions = sessionReplayModel.sessionReplayOptions else {
            Log.e("[SessionReplay] missing sessionReplayOptions")
            return .failure(.missingSessionReplayOptions)
        }

        var updatedProperties = properties ?? [:]
        updatedProperties[Keys.timestamp.rawValue] = Date().timeIntervalSince1970

        if sessionReplayOptions.recordingType == .image {
            guard sessionReplayModel.isRecording else {
                Log.e("[SessionReplay] Session Replay not recording ...")
                return .failure(.notRecording)
            }
            return sessionReplayModel.captureImage(properties: updatedProperties)
        }
        return .success(())
    }

    public func isRecording() -> Bool {
        if isDummyInstance {
            Log.d("SessionReplay.isRecording() called on inactive instance (skipped by sampling)")
            return false
        }

        guard let sessionReplayModel = self.sessionReplayModel else {
            Log.e("[SessionReplay] missing SessionReplayModel")
            return false
        }
        return sessionReplayModel.isRecording
    }

    public func isInitialized() -> Bool {
        if isDummyInstance {
            Log.d("SessionReplay.isInitialized() called on inactive instance (skipped by sampling)")
            return false
        }
        return SessionReplay.initializationAttempted
    }

    public func update(sessionId: String) {
        if isDummyInstance {
            Log.d("SessionReplay.update() called on inactive instance (skipped by sampling)")
            return
        }

        guard let sessionReplayModel = self.sessionReplayModel else {
            Log.e("[SessionReplay] missing SessionReplayModel")
            return
        }
        sessionReplayModel.updateSessionId(with: sessionId)
    }

    internal func update(sessionReplayModel: SessionReplayModel?) {
        if isDummyInstance {
            Log.d("SessionReplay.update() called on inactive instance (skipped by sampling)")
            return
        }

        guard let model = sessionReplayModel else {
            Log.e("[SessionReplay] missing SessionReplayModel")
            return
        }
        self.sessionReplayModel = model
    }

    // MARK: - Debug Utilities

    public func getSessionReplayFolderPath() -> String? {
        if isDummyInstance {
            Log.d("SessionReplay.getSessionReplayFolderPath() called on inactive instance (skipped by sampling)")
            return nil
        }

        guard let coralogixSdk = SdkManager.shared.getCoralogixSdk(),
              coralogixSdk.isDebug() else {
            Log.d("[SessionReplay] getSessionReplayFolderPath() is only available in debug mode")
            return nil
        }

        guard let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            Log.e("[SessionReplay] Could not locate Documents directory")
            return nil
        }

        return documentsDirectory
            .appendingPathComponent("SessionReplay")
            .path
    }
}
