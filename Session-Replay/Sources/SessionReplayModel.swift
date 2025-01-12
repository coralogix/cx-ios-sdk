//
//  SessionReplayModel.swift
//  session-replay
//
//  Created by Tomer Har Yoffi on 24/12/2024.
//

import UIKit

class SessionReplayModel {
    private let urlManager = URLManager()
    private var urlObserver: URLObserver?
    private var sessionId: String = ""
    internal var trackNumber: Int = 0
    var captureTimer: Timer?
    private var isMaskingProcessorWorking = false
    var sessionReplayOptions: SessionReplayOptions?
    var isRecording = false  // Custom flag to track recording state
    private var debounceWorkItem: DispatchWorkItem? = nil
    private let debounceInterval: TimeInterval = 0.5 // 500 milliseconds
    
    init(sessionReplayOptions: SessionReplayOptions? = nil) {
        self.sessionReplayOptions = sessionReplayOptions
        self.urlObserver = URLObserver(urlManager: self.urlManager,
                                       sessionReplayOptions: sessionReplayOptions)
        self.createSessionReplayFolder()
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
    
    internal func captureImage() {
        // Cancel any ongoing debounce work
        debounceWorkItem?.cancel()
        
        // Create a new work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
                Log.e("No active window scene found")
                return
            }
            
            guard let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
                Log.e("No key window found")
                return
            }
            
            guard let sessionReplayOptions = self.sessionReplayOptions,
                  sessionReplayOptions.captureScale > 0,
                  sessionReplayOptions.captureCompressionQuality > 0 else {
                Log.e("Invalid capture scale or compression quality in sessionReplayOptions")
                return
            }
            
            guard !sessionId.isEmpty else {
                Log.e("Invalid sessionId")
                return
            }
            
            guard let data = window.captureScreenshot(scale: sessionReplayOptions.captureScale,
                                                      compressionQuality: sessionReplayOptions.captureCompressionQuality) else {
                Log.e("Failed to capture screenshot")
                return
            }
            
            let timestemp = Int(Date().timeIntervalSince1970 * 1000)
            let fileName = "SessionReplay/\(sessionId)_\(timestemp)_\(trackNumber).jpg"
            
            if let documentsDirectory = FileManager.default.urls(for: .documentDirectory,
                                                                 in: .userDomainMask).first {
                let fileURL = documentsDirectory.appendingPathComponent(fileName)
                
                DispatchQueue(label: "com.example.fileOperations").async {
                    self.saveImageToDocument(fileURL:fileURL, data: data)
                    
                    // Add URL to array and save it
                    self.urlManager.addURL(fileURL)
                    Utils.saveURLsToDisk(urls: self.urlManager.savedURLs)
                    self.updateSessionId(with: self.sessionId)
                }
            }
        }
        
        // Store the new work item and execute it after the debounce interval
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    internal func updateSessionId(with sessionId: String) {
        if sessionId == self.sessionId {
            // Increment track if the session ID is the same
            self.trackNumber += 1
        } else {
            // Set track to 0 and update the current session ID if it's a new session
            self.sessionId = sessionId
            self.trackNumber = 0
            self.clearSessionReplayFolder()
        }
    }
    
    private func clearSessionReplayFolder() {
        guard let documentsURL = getDocumentsDirectory() else {
            Log.e("Could not locate Documents directory.")
            return
        }
        
        let sessionReplayURL = documentsURL.appendingPathComponent("SessionReplay")
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: sessionReplayURL, includingPropertiesForKeys: nil, options: [])
            for fileURL in contents {
                try FileManager.default.removeItem(at: fileURL)
            }
            Log.d("All contents of SessionReplay folder have been deleted.")
        } catch {
            Log.e("Failed to clear SessionReplay folder: \(error.localizedDescription)")
        }
    }
    
    private func getDocumentsDirectory() -> URL? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    private func saveImageToDocument(fileURL: URL, data: Data) {
        do {
            try data.write(to: fileURL)
            Log.d("Screenshot saved to: \(fileURL.path)")
        } catch {
            Log.e("Error saving screenshot: \(error)")
        }
    }
    
    private func createSessionReplayFolder() {
        guard let documentsURL = getDocumentsDirectory() else {
            Log.e("Could not locate Documents directory.")
            return
        }
        
        let sessionReplayURL = documentsURL.appendingPathComponent("SessionReplay")
        
        if !FileManager.default.fileExists(atPath: sessionReplayURL.path) {
            do {
                try FileManager.default.createDirectory(at: sessionReplayURL, withIntermediateDirectories: true, attributes: nil)
                Log.d("SessionReplay folder created successfully at \(sessionReplayURL.path)")
            } catch {
                Log.e("Failed to create SessionReplay folder: \(error.localizedDescription)")
            }
        } else {
            Log.d("SessionReplay folder already exists at \(sessionReplayURL.path)")
        }
    }
}

extension UIView {
    func captureScreenshot(scale: CGFloat = UIScreen.main.scale, compressionQuality: CGFloat = 0.8) -> Data? {
        
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
