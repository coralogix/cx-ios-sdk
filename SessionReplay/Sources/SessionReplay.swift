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

/// Represents a mask region for session replay.
/// Used in the pull-based model where coordinates are provided at capture time.
public struct MaskRegion {
    /// Unique identifier for the mask region
    public let id: String
    
    /// X coordinate of the region's origin
    public let x: CGFloat
    
    /// Y coordinate of the region's origin
    public let y: CGFloat
    
    /// Width of the region
    public let width: CGFloat
    
    /// Height of the region
    public let height: CGFloat
    
    /// Device pixel ratio
    public let dpr: CGFloat
    
    /// Initializes a new MaskRegion.
    /// - Parameters:
    ///   - id: Unique identifier for the mask region
    ///   - x: X coordinate of the region's origin
    ///   - y: Y coordinate of the region's origin
    ///   - width: Width of the region
    ///   - height: Height of the region
    ///   - dpr: Device pixel ratio (default is 1.0)
    public init(id: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, dpr: CGFloat = 1.0) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.dpr = dpr
    }
    
    /// Converts the MaskRegion to a CGRect, applying the device pixel ratio.
    public func toCGRect() -> CGRect {
        return CGRect(x: x * dpr, y: y * dpr, width: width * dpr, height: height * dpr)
    }
}

/// Type alias for the mask regions provider callback.
/// Called at capture time to fetch current coordinates for registered region IDs.
/// Uses a pull-based model where coordinates are fetched on-demand since widget positions can change.
/// - Parameter ids: Array of registered region IDs that need masking
/// - Parameter completion: Callback with array of MaskRegion objects containing current coordinates
public typealias MaskRegionsProvider = (_ ids: [String], _ completion: @escaping ([MaskRegion]) -> Void) -> Void

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
    /// A value of 0% means no events will be sent, while 100% sends all events.
    /// Any value in between controls the percentage of events that are recorded and sent.
    public var sessionRecordingSampleRate: Int
    
    /// An array of text patterns to mask in the captured content. can be string or regex
    public var maskText: [String]?
    
    /// Whether  Credit card images should be masked in the captured content. On / Off
    public var maskOnlyCreditCards: Bool
    
    /// Whether all images should be masked in the captured content. 
    public var maskAllImages: Bool
    
    /// Whether faces should be masked in the captured content.
    public var maskFaces: Bool
    
    /// Determines if an image may contain a credit card based on specific text patterns.
    /// - Returns: An array of strings representing the text patterns that identify potential credit card content.
    ///
    /// The strings in this array are used to analyze text extracted from images. If any of these patterns
    /// are detected in the image, it is flagged as potentially containing a credit card. Examples of such
    /// patterns include "Visa", "MasterCard", or common credit card prefixes like "4" (for Visa).
    public var creditCardPredicate: [String]?
    
    /// Automatically starts session recording if enabled in the options.
    /// When `true`, the session recording begins automatically without requiring explicit invocation of `startSessionRecording`.
    public var autoStartSessionRecording: Bool
    
    /// Callback to fetch mask regions at capture time.
    /// Uses a pull-based model where coordinates are fetched on-demand since widget positions can change.
    /// - Note: Set this callback to enable dynamic masking of regions (e.g., Flutter widgets).
    public var maskRegionsProvider: MaskRegionsProvider?
    
    /// Initializes a new instance of `SessionReplayOptions` with the provided parameters.
    /// - Parameters:
    ///   - imageRecordingType: The type of recording (default is `image`).
    ///   - captureTimeInterval: The interval between captures (default is 10 seconds).
    ///   - captureScale: The scale factor for the captured images (default scale is 2).
    ///   - captureCompressionQuality: The compression quality for the images (default is 1.0).
    ///   - sessionRecordingSampleRate: The sampling rate for session recording events (default is `100%`).
    ///   - maskText: An optional array of text patterns to mask (default is `nil`).
    ///   - maskImages: Whether to mask specific images (default is `false`).
    ///   - maskAllImages: Whether to mask all images (default is `true`).
    ///   - maskFaces: Whether to mask faces (default is `false`).
    ///   - creditCardPredicate: An optional array of text, Determines if an image may contain a credit card based on specific text patterns. (default is `nil`).
    ///   - autoStartSessionRecording: Whether session recording starts automatically (default is `false`).
    ///   - maskRegionsProvider: Optional callback to fetch mask regions at capture time (default is `nil`).

    public init(recordingType: RecordingType = .image,
                captureTimeInterval: TimeInterval = 10,
                captureScale: CGFloat = 2.0,
                captureCompressionQuality: CGFloat = 1.0,
                sessionRecordingSampleRate: Int = 100,
                maskText: [String]? = nil,
                maskOnlyCreditCards: Bool = false,
                maskAllImages: Bool = true,
                maskFaces: Bool = false,
                creditCardPredicate: [String]? = nil,
                autoStartSessionRecording: Bool = false,
                maskRegionsProvider: MaskRegionsProvider? = nil) {
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
        self.maskRegionsProvider = maskRegionsProvider
    }
}

/// Manages session replay functionality, including recording and event capture.
public class SessionReplay: SessionReplayInterface {

    private static var initializationAttempted = false
    /// The internal model managing session replay data and operations.
    var sessionReplayModel: SessionReplayModel?
    
    // The shared instance using static let for thread safety
    public static var shared: SessionReplay! {
        get {
            guard _shared != nil else {
                Log.e("SessionReplay.shared accessed before initialization. Call SessionReplay.initializeWithOptions first.")
                return createDummyInstance()
            }
            return _shared
        }
    }
    
    // Private backing storage
    private static var _shared: SessionReplay?
    
    /// Pending mask region IDs registered before SessionReplay was initialized.
    /// These will be applied when SessionReplay is properly initialized.
    private static var pendingMaskRegionIds = Set<String>()
    private static let pendingRegionsQueue = DispatchQueue(label: "com.coralogix.sessionreplay.pendingregions")
    
    // Properties for storing options
    internal var sessionReplayOptions: SessionReplayOptions?

    // It's a design pattern to handle situations where initialization is skipped due
    // to sampling, so you can avoid null checks everywhere and safely no-op the API.
    internal var isDummyInstance = false

    // Private initializer that requires an Options object
    private init(sessionReplayOptions: SessionReplayOptions) {
        self.sessionReplayOptions = sessionReplayOptions
        self.sessionReplayModel = SessionReplayModel(sessionReplayOptions: sessionReplayOptions)
        
        // Apply any pending mask region registrations
        Self.applyPendingMaskRegions(to: self)
        
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
    
    /// Applies pending mask region registrations to the initialized SessionReplay instance.
    private static func applyPendingMaskRegions(to instance: SessionReplay) {
        pendingRegionsQueue.sync {
            guard !pendingMaskRegionIds.isEmpty else { return }
            
            for id in pendingMaskRegionIds {
                instance.sessionReplayModel?.maskedRegionIds.insert(id)
            }
            
            // Clear pending registrations
            pendingMaskRegionIds.removeAll()
        }
    }
    
    /// Queues a mask region ID for registration when SessionReplay is initialized.
    /// Called when registerMaskRegion is invoked before initialization.
    internal static func queuePendingMaskRegion(_ id: String) {
        pendingRegionsQueue.sync {
            pendingMaskRegionIds.insert(id)
        }
    }
    
    /// Removes a mask region ID from the pending queue.
    /// Called when unregisterMaskRegion is invoked before initialization.
    internal static func removePendingMaskRegion(_ id: String) {
        pendingRegionsQueue.sync {
            pendingMaskRegionIds.remove(id)
        }
    }

    // Method to initialize the singleton with options (called only once)
    public static func initializeWithOptions(sessionReplayOptions: SessionReplayOptions) {
        guard !initializationAttempted else {
            Log.e("SessionReplay initialization already attempted!")
            return
        }

        initializationAttempted = true

        // Check if we should initialize based on sampling
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
    
    /// Starts recording the session, capturing data at the configured interval.
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
            coralogixSdk.periodicallyCaptureEventTriggered()
            sessionReplayModel.captureTimer = Timer.scheduledTimer(withTimeInterval: sessionReplayOptions.captureTimeInterval, repeats: true) { _ in
                coralogixSdk.periodicallyCaptureEventTriggered()
            }
        }
    }
    
    /// Stops recording the session and releases resources.
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
        } else {
            // TBD:
        }
    }
    
    /// Captures a specific event during the session.
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
    
    /// Check is the Session replay is currently recording.
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
    
    /// Check is the Session replay is Initialized.
    public func isInitialized() -> Bool {
        if isDummyInstance {
            Log.d("SessionReplay.isInitialized() called on inactive instance (skipped by sampling)")
            return false
        }
        return SessionReplay.initializationAttempted
    }
    
    // MARK: - Mask Region Methods (Pull-Based Model)
    
    /// Registers a region ID that should be masked during session replay.
    /// Uses a pull-based model where the actual coordinates are fetched at capture time
    /// via the `maskRegionsProvider` callback.
    /// - Parameter id: Unique identifier for the region to mask
    public func registerMaskRegion(_ id: String) {
        if isDummyInstance {
            // Queue the registration for when SessionReplay is properly initialized
            SessionReplay.queuePendingMaskRegion(id)
            return
        }
        
        guard let sessionReplayModel = self.sessionReplayModel else {
            Log.e("[SessionReplay] missing SessionReplayModel")
            return
        }
        
        sessionReplayModel.maskedRegionIds.insert(id)
        Log.d("[SessionReplay] Registered mask region: \(id)")
    }
    
    /// Removes a region from the mask list.
    /// Called when a masked widget/view is disposed.
    /// - Parameter id: Unique identifier for the region to unregister
    public func unregisterMaskRegion(_ id: String) {
        if isDummyInstance {
            // Remove from pending queue if SessionReplay is not yet initialized
            SessionReplay.removePendingMaskRegion(id)
            return
        }
        
        guard let sessionReplayModel = self.sessionReplayModel else {
            Log.e("[SessionReplay] missing SessionReplayModel")
            return
        }

        sessionReplayModel.maskedRegionIds.remove(id)
        Log.d("[SessionReplay] Unregistered mask region: \(id)")
    }
    
    /// Returns the set of currently registered region IDs for masking.
    /// - Returns: Set of registered region IDs
    public func getMaskedRegionIds() -> Set<String> {
        if isDummyInstance {
            Log.d("SessionReplay.getMaskedRegionIds() called on inactive instance (skipped by sampling)")
            return Set<String>()
        }
        
        guard let sessionReplayModel = self.sessionReplayModel else {
            Log.e("[SessionReplay] missing SessionReplayModel")
            return Set<String>()
        }
        
        return sessionReplayModel.maskedRegionIds
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
    
    /// Returns the path to the session replay folder where screenshots are stored.
    /// Only returns the path when debug mode is enabled, otherwise returns nil.
    /// Useful for hybrid apps (Flutter, React Native) to access session replay files during development.
    /// - Returns: The absolute path to the SessionReplay folder, or nil if not in debug mode or not initialized.
    public func getSessionReplayFolderPath() -> String? {
        if isDummyInstance {
            Log.d("SessionReplay.getSessionReplayFolderPath() called on inactive instance (skipped by sampling)")
            return nil
        }
        
        // Only expose path in debug mode
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
        
        let sessionReplayPath = documentsDirectory
            .appendingPathComponent("SessionReplay")
            .path
        
        return sessionReplayPath
    }
}

