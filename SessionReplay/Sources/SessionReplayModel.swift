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
    private var debounceWorkItem: DispatchWorkItem? = nil
    private let debounceInterval: TimeInterval = 0.5 // 500 milliseconds
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
        // Cancel the debounce work item
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        
        // Invalidate any other timers (like idleTimer if present)
        captureTimer?.invalidate()
        captureTimer = nil
        
        Log.d("SessionManager deinitialized and resources cleaned up.")
    }
    
    internal func captureImage(properties: [String: Any]? = nil) {
        // Cancel any ongoing debounce work
        debounceWorkItem?.cancel()
        
        // Create a new work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            guard let window = self.getKeyWindow() else {
                Log.e("No key window found")
                return
            }
          
            guard let options = self.sessionReplayOptions,
                  self.isValidSessionReplayOptions(options) else {
                Log.e("Invalid sessionReplayOptions")
                return
            }
            
            guard !sessionId.isEmpty else {
                Log.e("Invalid sessionId")
                return
            }
            
            guard let screenshotData = window.captureScreenshot(scale: options.captureScale,
                                                      compressionQuality: options.captureCompressionQuality) else {
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
        
        // Store the new work item and execute it after the debounce interval
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
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

    internal func getKeyWindow(connectedScenes: Set<UIScene> = UIApplication.shared.connectedScenes) -> UIWindow? {
        guard let windowScene = connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            Log.e("No active window scene found")
            return nil
        }
        return windowScene.windows.first(where: { $0.isKeyWindow })
    }
    
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
        let timestamp = self.getTimestamp(from: properties)
        let screenshotId = self.getScreenshotId(from: properties)
        
        DispatchQueue(label: "com.coralogix.fileOperations").async { [weak self] in
            guard let self = self else { return }
            let point = self.getClickPoint(from: properties)
            Log.w("Handling point: \(point)")
            _ = self.saveImageToDocumentIfDebug(fileURL: fileURL, data: data)
            
            let completion: URLProcessingCompletion = { [weak self] isSuccess, originalTimestamp, originalScreenshotId  in
                _ = self?.compressAndSendData(data: data,
                                              timestamp: originalTimestamp,
                                              screenshotId: originalScreenshotId)
            }
            
            let urlEntry = URLEntry(url: fileURL,
                                    timestamp: timestamp,
                                    screenshotId: screenshotId,
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
    
    internal func compressAndSendData(data: Data, timestamp: TimeInterval, screenshotId: String) -> SessionReplayResultCode {
        if let compressedChunks = data.gzipCompressed(), compressedChunks.count > 0 {
            // Log.d("Compression succeeded! Number of chunks: \(compressedChunks.count)")
            for (index, chunk) in compressedChunks.enumerated() {
                // Log.d("Chunk \(index): \(chunk.count) bytes")
                let subIndex = calculateSubIndex(chunkCount: compressedChunks.count, currentIndex: index)
                let page =  "\(self.screenshotManager.page)"
                // Send Data
                self.srNetworkManager?.send(chunk,
                                            timestamp: timestamp,
                                            sessionId: self.sessionId.lowercased(),
                                            screenshotNumber: self.screenshotManager.screenshotCount,
                                            subIndex: subIndex,
                                            screenshotId: screenshotId,
                                            page: page) { result in
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

extension UIView {
    func captureScreenshot(scale: CGFloat = UIScreen.main.scale,
                           compressionQuality: CGFloat = 0.8) -> Data? {
        
        guard let keyWindow = getKeyWindow() else {
            return nil
        }
        
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = scale
        let renderer = UIGraphicsImageRenderer(bounds: keyWindow.bounds, format: rendererFormat)
        
        let image = renderer.image { context in
            keyWindow.drawHierarchy(in: keyWindow.bounds, afterScreenUpdates: true)
            
        }
        return image.jpegData(compressionQuality: compressionQuality)
    }
    
    func getKeyWindow() -> UIWindow? {
        guard let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }) // Filter only UIWindowScenes
            .flatMap({ $0.windows }) // Get all windows in each UIWindowScene
            .first(where: { $0.isKeyWindow }) // Find the key window
        else {
            Log.e("Unable to find the key window")
            return nil
        }
        return keyWindow
    }
}
