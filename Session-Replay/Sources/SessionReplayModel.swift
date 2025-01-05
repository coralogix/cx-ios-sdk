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

    init(sessionReplayOptions: SessionReplayOptions? = nil) {
        self.sessionReplayOptions = sessionReplayOptions
        self.urlObserver = URLObserver(urlManager: self.urlManager,
                                       sessionReplayOptions: sessionReplayOptions)
        self.createSessionReplayFolder()
    }
    
    internal func captureImage() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let sessionReplayOptions = self.sessionReplayOptions,
              let data = window.captureScreenshot(scale: sessionReplayOptions.captureScale,
                                                  compressionQuality: sessionReplayOptions.captureCompressionQuality) else {
            Log.e("Failed to capture screenshot")
            return
        }
        
        let timestemp = Int(Date().timeIntervalSince1970 * 1000)
        let fileName = "SessionReplay/\(sessionId)_\(timestemp)_\(trackNumber).jpg"
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory,
                                                             in: .userDomainMask).first {
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            self.saveImageToDocument(fileURL:fileURL, data: data)
            
            // Add URL to array and save it
            self.urlManager.addURL(fileURL)
            Helper.saveURLsToDisk(urls: self.urlManager.savedURLs)
            self.updateSessionId(with: self.sessionId)
        }
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
        guard let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else {
            print("Unable to find the key window")
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
}
