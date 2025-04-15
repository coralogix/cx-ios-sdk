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
    /// The type of recording to be used during the session. image / video (TBD)
    public var imageRecordingType: Bool
    
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
    
    /// Whether  images should be masked in the captured content. On / Off
    public var maskImages: Bool
    
    /// Whether all images should be masked in the captured content. if set to false only Credit Card Images will be masked
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
    
    /// Initializes a new instance of `SessionReplayOptions` with the provided parameters.
    /// - Parameters:
    ///   - imageRecordingType: The type of recording (default is `image`).
    ///   - captureTimeInterval: The interval between captures (default is 10 seconds).
    ///   - captureScale: The scale factor for the captured images (default is the screen scale).
    ///   - captureCompressionQuality: The compression quality for the images (default is 1.0).
    ///   - sessionRecordingSampleRate: The sampling rate for session recording events (default is `100%`).
    ///   - maskText: An optional array of text patterns to mask (default is `nil`).
    ///   - maskImages: Whether to mask specific images (default is `false`).
    ///   - maskAllImages: Whether to mask all images (default is `true`).
    ///   - maskFaces: Whether to mask faces (default is `false`).
    ///   - creditCardPredicate: An optional array of text, Determines if an image may contain a credit card based on specific text patterns. (default is `nil`).
    ///   - autoStartSessionRecording: Whether session recording starts automatically (default is `false`).

    public init(imageRecordingType: Bool = true,
                captureTimeInterval: TimeInterval = 10,
                captureScale: CGFloat = UIScreen.main.scale,
                captureCompressionQuality: CGFloat = 1.0,
                sessionRecordingSampleRate: Int = 100,
                maskText: [String]? = nil,
                maskImages: Bool = false,
                maskAllImages: Bool = true,
                maskFaces: Bool = false,
                creditCardPredicate: [String]? = nil,
                autoStartSessionRecording: Bool = false) {
        self.imageRecordingType = imageRecordingType
        self.captureTimeInterval = captureTimeInterval
        self.captureScale = captureScale
        self.captureCompressionQuality = captureCompressionQuality
        self.maskText = maskText
        self.maskImages = maskImages
        self.maskFaces = maskFaces
        self.maskAllImages = maskAllImages
        self.creditCardPredicate = creditCardPredicate
        self.autoStartSessionRecording = autoStartSessionRecording
        self.sessionRecordingSampleRate = sessionRecordingSampleRate
    }
}

/// Manages session replay functionality, including recording and event capture.
public class SessionReplay: SessionReplayInterface {
    
    /// The internal model managing session replay data and operations.
    var sessionReplayModel: SessionReplayModel?
    
    // The shared instance using static let for thread safety
    public static var shared: SessionReplay! = nil
    
    // Properties for storing options
    private var sessionReplayOptions: SessionReplayOptions?
    
    // Private initializer that requires an Options object
    private init(sessionReplayOptions: SessionReplayOptions) {
        guard Utils.shouldInitialized(sampleRate: sessionReplayOptions.sessionRecordingSampleRate) else {
            Log.e("Initialization skipped due to sample rate")
            return
        }
        
        self.sessionReplayOptions = sessionReplayOptions
        self.sessionReplayModel = SessionReplayModel(sessionReplayOptions: sessionReplayOptions)
        
        // Register with SDK Manager
        DispatchQueue.main.async {
            SdkManager.shared.register(sessionReplayInterface: self)
        }
        
        guard let coralogixSdk = SdkManager.shared.getCoralogixSdk() else {
            Log.e("[CoralogixSdk] is not initialized")
            return
        }
        
        let sessionId = coralogixSdk.getSessionID()
        self.update(sessionId: sessionId)
        
        if sessionReplayOptions.autoStartSessionRecording {
            self.startRecording()
        }
    }

    // Method to initialize the singleton with options (called only once)
    public static func initializeWithOptions(sessionReplayOptions: SessionReplayOptions) {
        guard shared == nil else {
            Log.e("Singleton already initialized!")
            return
        }
        
        // Create the singleton instance using options
        shared = SessionReplay(sessionReplayOptions: sessionReplayOptions)
    }
    
    /// Starts recording the session, capturing data at the configured interval.
    public func startRecording() {
        guard let sessionReplayModel = self.sessionReplayModel,
              let sessionReplayOptions = sessionReplayModel.sessionReplayOptions else {
            Log.e("[SessionReplay] missing sessionReplayOptions")
            return
        }
        
        if sessionReplayOptions.imageRecordingType == true {
            guard !sessionReplayModel.isRecording else { return }
            sessionReplayModel.isRecording = true
            
            sessionReplayModel.captureImage()
            sessionReplayModel.captureTimer = Timer.scheduledTimer(withTimeInterval: sessionReplayOptions.captureTimeInterval, repeats: true) { _ in
                sessionReplayModel.captureImage()
            }
        }
    }
    
    /// Stops recording the session and releases resources.
    public func stopRecording() {
        guard let sessionReplayModel = self.sessionReplayModel,
              let sessionReplayOptions = sessionReplayModel.sessionReplayOptions else {
            Log.e("[SessionReplay] missing sessionReplayOptions")
            return
        }
        
        if sessionReplayOptions.imageRecordingType == true {
            sessionReplayModel.isRecording = false
            sessionReplayModel.captureTimer?.invalidate()
        } else {
            // TBD:
        }
    }
    
    /// Captures a specific event during the session.
    public func captureEvent(properties: [String : Any]?) {
        guard let sessionReplayModel = self.sessionReplayModel,
              let sessionReplayOptions = sessionReplayModel.sessionReplayOptions else {
            Log.e("[SessionReplay] missing sessionReplayOptions")
            return
        }
        
        if sessionReplayOptions.imageRecordingType == true {
            guard sessionReplayModel.isRecording else { return }
            sessionReplayModel.captureImage(properties: properties)
        }
    }
    
    public func update(sessionId: String) {
        guard let sessionReplayModel = self.sessionReplayModel else {
            Log.e("[SessionReplay] missing SessionReplayModel")
            return
        }
        sessionReplayModel.updateSessionId(with: sessionId)
    }
    
    internal func update(sessionReplayModel: SessionReplayModel?) {
        guard let model = sessionReplayModel else {
            Log.e("[SessionReplay] missing SessionReplayModel")
            return
        }
        self.sessionReplayModel = model
    }
}

