//
//  SessionReplayModel.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 24/12/2024.
//

import UIKit
import CoralogixInternal
import CoreImage

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
    private var prvScreenshotData: Data? = nil
    private lazy var comparisonContext = CIContext(options: [.workingColorSpace: NSNull()])

    internal var getKeyWindow: () -> UIWindow? = {
        Global.getKeyWindow()
    }
    
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
    
    internal func prepareScreenshotIfNeeded(properties: [String: Any]?) -> Data? {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.captureImage(properties: properties)
            }
            return nil
        }
        
        guard let window = getKeyWindow() else {
            Log.e("No key window found")
            return nil
        }
        
        guard let options = self.sessionReplayOptions,
              self.isValidSessionReplayOptions(options) else {
            Log.e("Invalid sessionReplayOptions")
            return nil
        }
        
        return window.captureScreenshot(
            scale: options.captureScale,
            compressionQuality: options.captureCompressionQuality
        )
    }
    
    internal func saveScreenshotToFileSystem(
        screenshotData: Data,
        properties: [String: Any]?
    ) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                Log.e("Failed to locate documents directory")
                return
            }
            
            if let fileName = self?.generateFileName(properties: properties) {
                let fileURL = documentsDirectory
                    .appendingPathComponent("SessionReplay")
                    .appendingPathComponent(fileName)
                
                self?.handleCapturedData(
                    fileURL: fileURL,
                    data: screenshotData,
                    properties: properties
                )
            }
        }
    }
    
    internal func captureImage(properties: [String: Any]? = nil) -> Result<Void, CaptureEventError> {
        guard !sessionId.isEmpty else {
            Log.e("[SessionReplayModel] Invalid sessionId")
            return .failure(.invalidSessionId)
        }
        
        guard let screenshotData = properties?[Keys.screenshotData.rawValue] as? Data else {
            return self.captureAutomatic(properties: properties)
        }
       
        self.captureManual(properties: properties, screenshotData: screenshotData)
        return .success(())
    }
    
    internal func captureAutomatic(properties: [String: Any]?) -> Result<Void, CaptureEventError> {
        if let screenshotData = prepareScreenshotIfNeeded(properties: properties) {
            if let prvScreenshotData = prvScreenshotData, !self.imagesAreDifferent(screenshotData, prvScreenshotData) {
                Log.d("[SessionReplayModel] Same screenshot, skipping...")
                return .failure(.skippingEvent)
            }
            
            prvScreenshotData = screenshotData
            saveScreenshotToFileSystem(screenshotData: screenshotData, properties: properties)
            return .success(())
        }
        return .failure(.captureFailed)
    }
    
    internal func captureManual(properties: [String: Any]?, screenshotData: Data) {
        saveScreenshotToFileSystem(screenshotData: screenshotData, properties: properties)
    }
    
    internal func updateSessionId(with sessionId: String) {
        if sessionId != self.sessionId {
            self.sessionId = sessionId
            self.prvScreenshotData = nil
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
    
    internal func getSegmentIndex(from properties: [String: Any]?) -> Int {
        return (properties?[Keys.segmentIndex.rawValue] as? Int) ?? 0
    }
    
    internal func getPage(from properties: [String: Any]?) -> String {
        guard let properties = properties,
              let page = properties[Keys.page.rawValue] as? Int else {
            return "Unknown"
        }
        return "\(page)"
    }
    
    internal func generateFileName(properties: [String: Any]?) -> String {
        guard let properties = properties,
              let segmentIndex = properties[Keys.segmentIndex.rawValue] as? Int,
              let page = properties[Keys.page.rawValue] as? Int else {
            return "file_name_error"
        }
        
        return "\(sessionId)_\(page)_\(segmentIndex).jpg"
    }
    
    internal func handleCapturedData(fileURL: URL, data: Data, properties: [String: Any]?) {
        DispatchQueue(label: Keys.queueFileOperations.rawValue).async { [weak self] in
            guard let self = self else { return }
            let timestamp = self.getTimestamp(from: properties)
            let screenshotId = self.getScreenshotId(from: properties)
            let segmentIndex = self.getSegmentIndex(from: properties)
            let page = self.getPage(from: properties)
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
                                    segmentIndex: segmentIndex,
                                    page: page,
                                    screenshotData: data,
                                    point: point,
                                    completion: completion)
            
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
            //            let sizeInBytes = data.count
            //            let sizeInMB = Double(sizeInBytes) / (1024.0 * 1024.0)
            //            Log.d("Data size: \(String(format: "%.2f", sizeInMB)) MB")
            
            if let compressedChunks = data.gzipCompressed(), compressedChunks.count > 0 {
                //Log.d("Compression succeeded! Number of chunks: \(compressedChunks.count)")
                for (index, chunk) in compressedChunks.enumerated() {
                    // Log.d("Chunk \(index): \(chunk.count) bytes")
                    let subIndex = calculateSubIndex(chunkCount: compressedChunks.count, currentIndex: index)
                    
                    // Send Data
                    self.srNetworkManager?.send(chunk,
                                                urlEntry: urlEntry,
                                                sessionId: self.sessionId.lowercased(),
                                                subIndex: subIndex) { result in
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
    
    /// This function compares two images (from Data) by computing how different their pixels are on average.
    /// It doesn’t care about where the difference is — just how much overall.
    /// If the total difference is larger than a chosen threshold (like 1%), it says “yes, they’re different”.
    func imagesAreDifferent(_ data1: Data, _ data2: Data, threshold: Double = 0.01) -> Bool {
        guard
            let image1 = CIImage(data: data1),
            let image2 = CIImage(data: data2),
            image1.extent == image2.extent
        else {
            return true // invalid or different sizes → considered different
        }
        
        // Compute pixel-wise difference
        let diffFilter = CIFilter(name: "CIDifferenceBlendMode")!
        diffFilter.setValue(image1, forKey: kCIInputImageKey)
        diffFilter.setValue(image2, forKey: kCIInputBackgroundImageKey)
        guard let diffImage = diffFilter.outputImage else { return true }
        
        // Get average difference color (aggregate diff intensity)
        let extentVector = CIVector(x: diffImage.extent.origin.x,
                                    y: diffImage.extent.origin.y,
                                    z: diffImage.extent.size.width,
                                    w: diffImage.extent.size.height)
        
        guard let avgFilter = CIFilter(name: "CIAreaAverage",
                                       parameters: [kCIInputImageKey: diffImage,
                                                   kCIInputExtentKey: extentVector]),
              let outputImage = avgFilter.outputImage else {
            return true
        }
        
        // Render 1×1 pixel average into RGBA buffer
        var bitmap = [UInt8](repeating: 0, count: 4)
        comparisonContext.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: nil)
        
        // Calculate normalized RGB difference [0–1]
        let avgDiff = (Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])) / (3.0 * 255.0)
        
        return avgDiff > threshold
    }
}

