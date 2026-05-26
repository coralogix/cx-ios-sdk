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
    case success
    case failure
}

public class SessionReplayModel {
    internal var urlManager = URLManager()
    private var urlObserver: URLObserver?
    internal var sessionId: String = ""
    var captureTimer: Timer?
    var sessionReplayOptions: SessionReplayOptions?
    var isRecording = false
    private let srNetworkManager: SRNetworkManager?

    private let screenshotDataQueue = DispatchQueue(label: "com.coralogix.sessionReplay.screenshotDataQueue")
    private var _prvScreenshotData: Data? = nil

    /// Serial queue for off-main JPEG encoding. Serial so skip-identical comparison
    /// sees _prvScreenshotData updates in capture order.
    internal let encodingQueue = DispatchQueue(
        label: "com.coralogix.sessionReplay.encodingQueue",
        qos: .userInitiated
    )

    private lazy var comparisonContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// Monotonic counter passed to flutterViewBitmapProvider as frameId.
    private var captureFrameCounter: Int64 = 0

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
        captureTimer?.invalidate()
        captureTimer = nil
        Log.d("SessionManager deinitialized and resources cleaned up.")
    }

    // MARK: - Screenshot capture

    /// Captures a screenshot of all visible windows with synchronous UIView-walk masking.
    /// For the Flutter path, `flutterCGImage` and `flutterViewRect` carry the pre-masked
    /// Dart bitmap and its position in screen points.
    /// Must be called on the main thread.
    private func prepareScreenshotImageOnMain(
        options: SessionReplayOptions,
        flutterCGImage: CGImage?,
        flutterViewRect: CGRect?
    ) -> UIImage? {
        guard Thread.isMainThread else { return nil }
        guard isValidSessionReplayOptions(options) else {
            Log.e("Invalid sessionReplayOptions")
            return nil
        }
        return UIView().captureScreenshotImage(
            scale: options.captureScale,
            maskAllTexts: options.maskAllTexts,
            textsToMask: options.textsToMask ?? [],
            maskAllImages: options.maskAllImages,
            flutterCGImage: flutterCGImage,
            flutterViewRect: flutterViewRect
        )
    }

    /// Legacy signature kept for test compatibility and the synchronous captureAutomatic path.
    internal func prepareScreenshotImageOnMain(properties: [String: Any]?) -> UIImage? {
        guard let options = sessionReplayOptions else { return nil }
        return prepareScreenshotImageOnMain(options: options, flutterCGImage: nil, flutterViewRect: nil)
    }

    /// Synchronous capture-and-encode, retained as a back-compat shim.
    internal func prepareScreenshotIfNeeded(properties: [String: Any]?) -> Data? {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                _ = self?.captureImage(properties: properties)
            }
            return nil
        }

        guard let image = prepareScreenshotImageOnMain(properties: properties),
              let quality = sessionReplayOptions?.captureCompressionQuality else {
            return nil
        }
        return image.jpegData(compressionQuality: quality)
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
        // Flutter path: Dart rasterises + masks in one synchronous slice and pushes
        // the pre-masked bitmap to native. Async — returns immediately.
        if sessionReplayOptions?.flutterViewBitmapProvider != nil {
            captureAutomaticFlutter(properties: properties)
            return .success(())
        }

        // Native path: synchronous UIView walk on main thread, encode off-main.
        let renderStart = Date()
        guard let image = prepareScreenshotImageOnMain(properties: properties),
              let options = sessionReplayOptions else {
            return .failure(.captureFailed)
        }
        let renderMs = Date().timeIntervalSince(renderStart) * 1_000
        Log.d("[SR-perf] render \(String(format: "%.1f", renderMs))ms")

        let callerIncrementedCounter = properties?[Keys.segmentIndex.rawValue] as? Int != nil
        encodeAndProcess(
            image: image,
            compressionQuality: options.captureCompressionQuality,
            properties: properties,
            callerIncrementedCounter: callerIncrementedCounter
        )
        return .success(())
    }

    /// Flutter async capture path.
    ///
    /// Calls `flutterViewBitmapProvider` on the main thread; the provider invokes
    /// `captureMaskedFlutterView` on the Flutter MethodChannel and delivers the
    /// pre-masked RGBA bitmap via a callback that also fires on the main thread.
    /// No blocking wait — the run loop handles the round-trip.
    private func captureAutomaticFlutter(properties: [String: Any]?) {
        guard let options = sessionReplayOptions,
              let provider = options.flutterViewBitmapProvider else { return }

        captureFrameCounter &+= 1
        let frameId = captureFrameCounter
        let callerIncrementedCounter = properties?[Keys.segmentIndex.rawValue] as? Int != nil

        // Locate the FlutterView on screen synchronously before yielding.
        let flutterViewRect = findFlutterViewRect()

        // No FlutterView visible — capture native windows only.
        guard let rect = flutterViewRect else {
            guard let image = prepareScreenshotImageOnMain(
                options: options, flutterCGImage: nil, flutterViewRect: nil
            ) else {
                if callerIncrementedCounter {
                    SdkManager.shared.getCoralogixSdk()?.revertScreenshotCounter()
                }
                return
            }
            encodeAndProcess(image: image, compressionQuality: options.captureCompressionQuality,
                             properties: properties, callerIncrementedCounter: callerIncrementedCounter)
            return
        }

        // viewId is intentionally "implicit_view" — the cx-flutter-plugin ignores it (uses `_`)
        // and routes all captures to Flutter's single implicit view. Only frameId matters.
        provider("implicit_view", frameId) { [weak self] bitmap in
            guard let self = self, let options = self.sessionReplayOptions else { return }

            let flutterCGImage = bitmap.flatMap { Self.makeCGImage(from: $0) }

            guard let image = self.prepareScreenshotImageOnMain(
                options: options, flutterCGImage: flutterCGImage, flutterViewRect: rect
            ) else {
                if callerIncrementedCounter {
                    SdkManager.shared.getCoralogixSdk()?.revertScreenshotCounter()
                }
                return
            }

            self.encodeAndProcess(image: image, compressionQuality: options.captureCompressionQuality,
                                  properties: properties, callerIncrementedCounter: callerIncrementedCounter)
        }
    }

    /// Converts a `FlutterViewBitmap` (RGBA8888 premul, device-DPR resolution) to a CGImage
    /// that can be composited inside `UIGraphicsImageRenderer`.
    private static func makeCGImage(from bitmap: FlutterViewBitmap) -> CGImage? {
        guard let provider = CGDataProvider(data: bitmap.bytes as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(
            width: bitmap.width,
            height: bitmap.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bitmap.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Walks all visible windows in the active scene to find the first FlutterView,
    /// then returns its frame in screen coordinates (UIKit points). Must be called
    /// on the main thread. Returns nil when no FlutterView is on screen.
    private func findFlutterViewRect() -> CGRect? {
        guard Thread.isMainThread else { return nil }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return nil }

        let windows = scene.windows
            .filter { !$0.isHidden && $0.alpha > 0 }
            .sorted(by: { $0.windowLevel < $1.windowLevel })

        for window in windows {
            if let flutterView = UIView.findFlutterViewInSubtree(window) {
                return flutterView.convert(flutterView.bounds, to: nil)
            }
        }
        return nil
    }

    /// JPEG-encodes the captured image off the main thread, performs the
    /// skip-identical check, and saves to disk if the frame is new.
    internal func encodeAndProcess(
        image: UIImage,
        compressionQuality: CGFloat,
        properties: [String: Any]?,
        callerIncrementedCounter: Bool
    ) {
        encodingQueue.async { [weak self] in
            guard let self = self else { return }

            let encodeStart = Date()
            guard let screenshotData = image.jpegData(compressionQuality: compressionQuality) else {
                if callerIncrementedCounter {
                    SdkManager.shared.getCoralogixSdk()?.revertScreenshotCounter()
                }
                return
            }
            let encodeMs = Date().timeIntervalSince(encodeStart) * 1_000
            Log.d("[SR-perf] encode \(String(format: "%.1f", encodeMs))ms size=\(screenshotData.count)B")

            let shouldSkip = self.screenshotDataQueue.sync { () -> Bool in
                if let prvData = self._prvScreenshotData,
                   !self.imagesAreDifferent(screenshotData, prvData) {
                    return true
                }
                self._prvScreenshotData = screenshotData
                return false
            }

            if shouldSkip {
                Log.d("[SR-perf] SKIP duplicate frame")
                if callerIncrementedCounter {
                    SdkManager.shared.getCoralogixSdk()?.revertScreenshotCounter()
                }
                return
            }

            Log.d("[SR-perf] dispatching upload \(screenshotData.count)B")
            self.saveScreenshotToFileSystem(screenshotData: screenshotData, properties: properties)
        }
    }

    internal func captureManual(properties: [String: Any]?, screenshotData: Data) {
        saveScreenshotToFileSystem(screenshotData: screenshotData, properties: properties)
    }

    internal func updateSessionId(with sessionId: String) {
        if sessionId != self.sessionId {
            self.sessionId = sessionId
            screenshotDataQueue.sync { _prvScreenshotData = nil }
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
                Log.d("[SessionReplayModel] folder created successfully at \(sessionReplayURL.path)")
                return .success
            } catch {
                Log.e("Failed to create SessionReplay folder: \(error.localizedDescription)")
                return .failure
            }
        } else {
            Log.d("[SessionReplayModel] folder already exists at \(sessionReplayURL.path)")
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
        let segmentIndex: Int
        let page: Int

        if let providedSegmentIndex = properties?[Keys.segmentIndex.rawValue] as? Int,
           let providedPage = properties?[Keys.page.rawValue] as? Int {
            segmentIndex = providedSegmentIndex
            page = providedPage
        } else if let coralogixSdk = SdkManager.shared.getCoralogixSdk() {
            let locationProps = coralogixSdk.getNextScreenshotLocationProperties()
            segmentIndex = locationProps[Keys.segmentIndex.rawValue] as? Int ?? 0
            page = locationProps[Keys.page.rawValue] as? Int ?? 0
        } else {
            Log.e("[SessionReplayModel] Cannot generate file name: no properties and CoralogixRum not available")
            segmentIndex = 0
            page = 0
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

            let completion: URLProcessingCompletion = { [weak self] ciImage, urlEntry in
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
        guard let properties = properties else { return nil }
        if let positionX = properties[Keys.positionX.rawValue] as? CGFloat,
           let positionY = properties[Keys.positionY.rawValue] as? CGFloat {
            return CGPoint(x: positionX, y: positionY)
        }
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
            if let compressedChunks = data.gzipCompressed(), compressedChunks.count > 0 {
                for (index, chunk) in compressedChunks.enumerated() {
                    let subIndex = calculateSubIndex(chunkCount: compressedChunks.count, currentIndex: index)
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

    func imagesAreDifferent(_ data1: Data, _ data2: Data, threshold: Double = 0.01) -> Bool {
        guard
            let image1 = CIImage(data: data1),
            let image2 = CIImage(data: data2),
            image1.extent == image2.extent
        else {
            return true
        }

        let diffFilter = CIFilter(name: "CIDifferenceBlendMode")!
        diffFilter.setValue(image1, forKey: kCIInputImageKey)
        diffFilter.setValue(image2, forKey: kCIInputBackgroundImageKey)
        guard let diffImage = diffFilter.outputImage else { return true }

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

        var bitmap = [UInt8](repeating: 0, count: 4)
        comparisonContext.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: nil)

        let avgDiff = (Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])) / (3.0 * 255.0)
        return avgDiff > threshold
    }
}
