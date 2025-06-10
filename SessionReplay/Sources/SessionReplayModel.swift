//
//  SessionReplayModel.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 24/12/2024.
//

import UIKit
import CoralogixInternal

/// The possible results for the export method.
public enum SessionReplayResultCode {
    /// The export operation finished successfully.
    case success
    
    /// The export operation finished with an error.
    case failure
}

class SessionReplayModel {
    internal var urlManager = URLManager()
    private var urlObserver: URLObserver?
    internal var sessionId: String = ""
    var captureTimer: Timer?
    private var isMaskingProcessorWorking = false
    var sessionReplayOptions: SessionReplayOptions?
    var isRecording = false  // Custom flag to track recording state
    private let srNetworkManager: SRNetworkManager?
    internal let screenshotManager = ScreenshotManager()
    
    init(sessionReplayOptions: SessionReplayOptions? = nil,
         networkManager: SRNetworkManager? = SRNetworkManager()) {
        self.sessionReplayOptions = sessionReplayOptions
        self.srNetworkManager = networkManager
        self.urlObserver = URLObserver(urlManager: self.urlManager,
                                       sessionReplayOptions: sessionReplayOptions)
        _ = self.createSessionReplayFolder()
    }
    
    deinit {
        // Invalidate any other timers (like idleTimer if present)
        captureTimer?.invalidate()
        captureTimer = nil
        
        Log.d("SessionManager deinitialized and resources cleaned up.")
    }
    
    internal func captureImage(properties: [String: Any]? = nil) {
        guard !sessionId.isEmpty else {
            Log.e("Invalid sessionId")
            return
        }
        
        var screenshotData: Data? = properties?[Keys.screenshotData.rawValue] as? Data
        
        if screenshotData == nil {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { self.captureImage(properties: properties) }
                return
            }
            
            guard let window = Global.getKeyWindow() else {
                Log.e("No key window found")
                return
            }
            
            guard let options = self.sessionReplayOptions,
                  self.isValidSessionReplayOptions(options) else {
                Log.e("Invalid sessionReplayOptions")
                return
            }
            
            screenshotData = window.captureScreenshot(
                scale: options.captureScale,
                compressionQuality: options.captureCompressionQuality
            )
        }
        
        guard let screenshotData else {
            Log.e("Failed to capture screenshot")
            return
        }
        
        self.screenshotManager.takeScreenshot()
        let fileName = self.generateFileName()
        
        if let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            let fileURL = documentsDirectory
                .appendingPathComponent("SessionReplay")
                .appendingPathComponent(fileName)
            self.handleCapturedData(fileURL: fileURL,
                                    data: screenshotData,
                                    properties: properties)
        }
    }
    
    internal func updateSessionId(with sessionId: String) {
        if sessionId != self.sessionId {
            self.sessionId = sessionId
            self.screenshotManager.resetSession()
            _ = self.clearSessionReplayFolder()
            SRUtils.deleteURLsFromDisk()
        }
    }
    
    internal func clearSessionReplayFolder(fileManager: FileManager = .default) -> SessionReplayResultCode {
        guard let documentsURL = getDocumentsDirectory(fileManager: fileManager) else {
            Log.e("Could not locate Documents directory.")
            return .failure
        }
        
        let sessionReplayURL = documentsURL.appendingPathComponent("SessionReplay")
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: sessionReplayURL,
                                                               includingPropertiesForKeys: nil,
                                                               options: [])
            if contents.count > 0 {
                for fileURL in contents {
                    try fileManager.removeItem(at: fileURL)
                }
                Log.d("All contents of SessionReplay folder have been deleted.")
                return .success
            }
            return .failure
        } catch {
            Log.e("Failed to clear SessionReplay folder: \(error.localizedDescription)")
            return .failure
        }
    }
    
    internal func getDocumentsDirectory(fileManager: FileManager = .default) -> URL? {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    internal func saveImageToDocument(fileURL: URL, data: Data) -> SessionReplayResultCode {
        do {
            try data.write(to: fileURL)
            return .success
        } catch {
            Log.e("Error saving screenshot: \(error)")
            return .failure
        }
    }
    
    internal func createSessionReplayFolder(fileManager: FileManager = .default) -> SessionReplayResultCode {
        guard let documentsURL = getDocumentsDirectory(fileManager: fileManager) else {
            Log.e("Could not locate Documents directory.")
            return .failure
        }
        
        let sessionReplayURL = documentsURL.appendingPathComponent("SessionReplay")
        
        if !fileManager.fileExists(atPath: sessionReplayURL.path) {
            do {
                try fileManager.createDirectory(at: sessionReplayURL, withIntermediateDirectories: true, attributes: nil)
                Log.d("SessionReplay folder created successfully at \(sessionReplayURL.path)")
                return .success
            } catch {
                Log.e("Failed to create SessionReplay folder: \(error.localizedDescription)")
                return .failure
            }
        } else {
            Log.d("SessionReplay folder already exists at \(sessionReplayURL.path)")
            return .failure
        }
    }
    
    // MARK: - Helper Methods
    internal func isValidSessionReplayOptions(_ options: SessionReplayOptions) -> Bool {
        return options.captureScale > 0 && options.captureCompressionQuality > 0
    }
    
    internal func getTimestamp(from properties: [String: Any]?) -> TimeInterval {
        return (properties?[Keys.timestamp.rawValue] as? TimeInterval) ?? Date().timeIntervalSince1970 * 1000
    }
    
    internal func getScreenshotId(from properties: [String: Any]?) -> String {
        return (properties?[Keys.screenshotId.rawValue] as? String) ?? UUID().uuidString.lowercased()
    }
    
    internal func generateFileName() -> String {
        return "\(sessionId)_\(self.screenshotManager.screenshotCount).jpg"
    }
    
    internal func handleCapturedData(fileURL: URL, data: Data, properties: [String: Any]?) {
        DispatchQueue(label: "com.coralogix.fileOperations").async { [weak self] in
            guard let self = self else { return }
            let timestamp = self.getTimestamp(from: properties)
            let screenshotId = self.getScreenshotId(from: properties)
            let point = self.getClickPoint(from: properties)
            
            let completion: URLProcessingCompletion = { [weak self] ciImage, urlEntry  in
                if let ciImage = ciImage,
                   let ciImageData = Global.ciImageToData(ciImage) {
                    if let sdkManager = SdkManager.shared.getCoralogixSdk(), sdkManager.isDebug() {
                        SRUtils.saveImage(ciImage, outputURL: fileURL) { _ in }
                    }
                    _ = self?.compressAndSendData(data: ciImageData, urlEntry: urlEntry)
                }
            }
            
            let urlEntry = URLEntry(url: fileURL,
                                    timestamp: timestamp,
                                    screenshotId: screenshotId,
                                    screenshotData: data,
                                    completion: completion,
                                    point: point)
            
            self.urlManager.addURL(urlEntry: urlEntry)
            self.updateSessionId(with: self.sessionId)
        }
    }
    
    internal func getClickPoint(from properties: [String: Any]?) -> CGPoint? {
        // Safely unwrap the dictionary
        guard let properties = properties else {
            return nil
        }
        // Check if the dictionary contains valid x and y values
        if let positionX = properties[Keys.positionX.rawValue] as? CGFloat,
           let positionY = properties[Keys.positionY.rawValue] as? CGFloat {
            return CGPoint(x: positionX, y: positionY)
        }
        // Return nil if the dictionary doesn't contain valid values
        return nil
    }
    
    internal func saveImageToDocumentIfDebug(fileURL: URL, data: Data) -> SessionReplayResultCode {
        if let sdkManager = SdkManager.shared.getCoralogixSdk(), sdkManager.isDebug() {
            return saveImageToDocument(fileURL: fileURL, data: data)
        }
        return .failure
    }
    
    internal func calculateSubIndex(chunkCount: Int, currentIndex: Int) -> Int {
        return chunkCount > 1 ? currentIndex : -1
    }
    
    internal func compressAndSendData(
        data: Data,
        urlEntry: URLEntry?) -> SessionReplayResultCode {
            let sizeInBytes = data.count
            let sizeInMB = Double(sizeInBytes) / (1024.0 * 1024.0)
            Log.d("Data size: \(String(format: "%.2f", sizeInMB)) MB")
            
            if let compressedChunks = data.gzipCompressed(), compressedChunks.count > 0 {
                Log.d("Compression succeeded! Number of chunks: \(compressedChunks.count)")
                for (index, chunk) in compressedChunks.enumerated() {
                    // Log.d("Chunk \(index): \(chunk.count) bytes")
                    let subIndex = calculateSubIndex(chunkCount: compressedChunks.count, currentIndex: index)

                    // Send Data
                    self.srNetworkManager?.send(chunk,
                                                urlEntry: urlEntry,
                                                sessionId: self.sessionId.lowercased(),
                                                screenshotNumber: self.screenshotManager.screenshotCount,
                                                subIndex: subIndex,
                                                page: "\(self.screenshotManager.page)") { result in
                        if result == .success {
                            if let sdkManager = SdkManager.shared.getCoralogixSdk() {
                                sdkManager.hasSessionRecording(true)
                            }
                        }
                    }
                }
                return .success
            } else {
                Log.e("Compression failed")
                return .failure
            }
        }
}

