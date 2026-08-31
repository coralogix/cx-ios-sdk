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

    // Guards the two fields below (same serial-queue-as-mutex pattern as
    // `screenshotDataQueue`). The provider callback runs on main; `updateSessionId`
    // runs off-main, so these are genuinely cross-thread.
    private let flutterFrameQueue = DispatchQueue(label: "com.coralogix.sessionReplay.flutterFrameQueue")

    /// A decoded Dart delivery: the bitmap together with the mask rects Dart reported for it
    /// (screen offsets applied later, at composite time). Pixels and geometry travel on one
    /// object so they can never be paired across frames.
    internal struct FlutterFrame {
        let image: CGImage
        let maskRects: [CGRect]
    }

    // frameId of the newest delivery already composited. A late, out-of-order callback
    // carrying an older frameId is dropped, not shipped behind the newer frame.
    private var _latestAcceptedFlutterFrameId: Int64 = 0
    // Bumped on every session rotation. A callback whose captured generation no
    // longer matches was requested in a previous session — its frame must not leak
    // forward into the new session.
    private var _flutterFrameGeneration: Int64 = 0
    internal var flutterFrameGeneration: Int64 { flutterFrameQueue.sync { _flutterFrameGeneration } }

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
    private func prepareCapturedFrameOnMain(
        options: SessionReplayOptions,
        flutterCGImage: CGImage?,
        flutterViewRect: CGRect?,
        flutterMaskRects: [CGRect] = [],
        isClickFrame: Bool = false
    ) -> CapturedFrame? {
        guard Thread.isMainThread else { return nil }
        guard isValidSessionReplayOptions(options) else {
            Log.e("Invalid sessionReplayOptions")
            return nil
        }
        return UIView().captureFrame(
            scale: options.captureScale,
            maskText: options.maskText,
            maskAllImages: options.maskAllImages,
            flutterCGImage: flutterCGImage,
            flutterViewRect: flutterViewRect,
            flutterMaskRects: flutterMaskRects,
            isClickFrame: isClickFrame
        )
    }

    /// Legacy signature kept for test compatibility and the synchronous captureAutomatic path.
    internal func prepareCapturedFrameOnMain(properties: [String: Any]?) -> CapturedFrame? {
        guard let options = sessionReplayOptions else { return nil }
        let isClickFrame = getClickPoint(from: properties) != nil
        return prepareCapturedFrameOnMain(options: options, flutterCGImage: nil, flutterViewRect: nil, isClickFrame: isClickFrame)
    }

    /// Synchronous capture-and-encode, retained as a back-compat shim.
    internal func prepareScreenshotIfNeeded(properties: [String: Any]?) -> Data? {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                _ = self?.captureImage(properties: properties)
            }
            return nil
        }

        guard let frame = prepareCapturedFrameOnMain(properties: properties),
              let quality = sessionReplayOptions?.captureCompressionQuality else {
            return nil
        }
        return frame.image.jpegData(compressionQuality: quality)
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

    /// `completion` — when supplied — fires exactly once with the outcome the return value
    /// cannot carry: whether a frame was actually encoded and queued for upload. Both capture
    /// paths finish after this call returns (the native one encodes off-main, the Flutter one
    /// waits on Dart), so a caller that stamps a span with screenshot attributes must wait for
    /// it rather than trust `.success` here.
    internal func captureImage(properties: [String: Any]? = nil,
                               completion: CaptureEventCompletion? = nil) -> Result<Void, CaptureEventError> {
        guard !sessionId.isEmpty else {
            Log.e("[SessionReplayModel] Invalid sessionId")
            completion?(.failure(.invalidSessionId))
            return .failure(.invalidSessionId)
        }

        guard let screenshotData = properties?[Keys.screenshotData.rawValue] as? Data else {
            return self.captureAutomatic(properties: properties, completion: completion)
        }

        self.captureManual(properties: properties, screenshotData: screenshotData)
        completion?(.success(()))
        return .success(())
    }

    internal func captureAutomatic(properties: [String: Any]?,
                                   completion: CaptureEventCompletion? = nil) -> Result<Void, CaptureEventError> {
        // Flutter path: Dart rasterises + masks in one synchronous slice and pushes
        // the pre-masked bitmap to native. Async — returns immediately.
        if sessionReplayOptions?.flutterViewBitmapProvider != nil {
            captureAutomaticFlutter(properties: properties, completion: completion)
            return .success(())
        }

        // Native path: synchronous UIView walk on main thread, encode off-main.
        guard let frame = prepareCapturedFrameOnMain(properties: properties),
              let options = sessionReplayOptions else {
            completion?(.failure(.captureFailed))
            return .failure(.captureFailed)
        }

        let callerIncrementedCounter = properties?[Keys.segmentIndex.rawValue] as? Int != nil
        encodeAndProcess(
            image: frame.image,
            compressionQuality: options.captureCompressionQuality,
            properties: propertiesWithCaptureMetadata(properties, maskRects: frame.maskRects),
            callerIncrementedCounter: callerIncrementedCounter,
            completion: completion
        )
        return .success(())
    }

    /// Flutter async capture path.
    ///
    /// Calls `flutterViewBitmapProvider` on the main thread; the provider invokes
    /// `captureMaskedFlutterView` on the Flutter MethodChannel and delivers the
    /// pre-masked RGBA bitmap via a callback that also fires on the main thread.
    /// No blocking wait — the run loop handles the round-trip. A `nil` delivery drops
    /// the capture; nothing is carried over from an earlier cycle.
    private func captureAutomaticFlutter(properties: [String: Any]?,
                                         completion: CaptureEventCompletion? = nil) {
        guard let options = sessionReplayOptions,
              let provider = options.flutterViewBitmapProvider else {
            completion?(.failure(.missingSessionReplayOptions))
            return
        }

        captureFrameCounter &+= 1
        let frameId = captureFrameCounter
        let callerIncrementedCounter = properties?[Keys.segmentIndex.rawValue] as? Int != nil
        let isClickFrame = getClickPoint(from: properties) != nil

        // Nothing shipped for this cycle: give the caller's screenshot index back (it was
        // minted for a frame that will never exist) and report the drop so no span advertises
        // a screenshot the backend never receives.
        let drop: () -> Void = {
            if callerIncrementedCounter {
                SdkManager.shared.getCoralogixSdk()?.revertScreenshotCounter()
            }
            completion?(.failure(.skippingEvent))
        }

        // Locate the FlutterView on screen synchronously before yielding.
        let flutterViewRect = findFlutterViewRect()

        // No FlutterView visible — capture native windows only.
        guard let rect = flutterViewRect else {
            guard let frame = prepareCapturedFrameOnMain(
                options: options, flutterCGImage: nil, flutterViewRect: nil, isClickFrame: isClickFrame
            ) else {
                drop()
                return
            }
            encodeAndProcess(image: frame.image, compressionQuality: options.captureCompressionQuality,
                             properties: propertiesWithCaptureMetadata(properties, maskRects: frame.maskRects),
                             callerIncrementedCounter: callerIncrementedCounter,
                             completion: completion)
            return
        }

        let requestGeneration = flutterFrameGeneration

        // The provider is host-app code (the Flutter plugin), so a second delivery for the
        // same cycle is possible; it must not composite twice or report the capture twice.
        // Plain captured state, not a lock: the contract puts the callback on main, and an
        // off-main delivery is already dropped by `prepareCapturedFrameOnMain`.
        var didAnswer = false

        // viewId is intentionally "implicit_view" — the cx-flutter-plugin ignores it (uses `_`)
        // and routes all captures to Flutter's single implicit view. Only frameId matters.
        //
        // isClick/tapTimestampMs let Dart hold a tap capture for the next committed frame
        // (or answer nil when the tap is already too stale to draw honestly) — the same
        // inputs the Android provider receives.
        provider("implicit_view", frameId, isClickFrame,
                 tapTimestampMilliseconds(from: properties, isClick: isClickFrame)) { [weak self] bitmap in
            guard !didAnswer else {
                Log.w("[SessionReplayModel] flutterViewBitmapProvider answered twice for frameId \(frameId) — ignoring")
                return
            }
            didAnswer = true

            guard let self = self, let options = self.sessionReplayOptions else {
                drop()
                return
            }

            // Drop a callback that outlived its session: its frame belongs to a
            // previous session and must not poison the new one. Reported to the caller like
            // any other drop, but without the counter revert — after a rotation the counter
            // belongs to the new session, so reverting would corrupt it; a one-index gap in
            // the old session is the lesser evil.
            guard self.flutterFrameGeneration == requestGeneration else {
                completion?(.failure(.skippingEvent))
                return
            }

            // nil = no frame for this cycle. Drop it — never black, never an earlier frame.
            guard let flutterFrame = self.resolveFlutterFrame(freshBitmap: bitmap, frameId: frameId) else {
                drop()
                return
            }

            // Re-snapshot rect at compositing time — Flutter view may have moved
            // during the async Dart round-trip. Fall back to pre-snapshotted rect
            // if the view is no longer visible (e.g., navigation transition).
            let compositeRect = self.findFlutterViewRect() ?? rect

            guard let frame = self.prepareCapturedFrameOnMain(
                options: options, flutterCGImage: flutterFrame.image, flutterViewRect: compositeRect,
                flutterMaskRects: flutterFrame.maskRects, isClickFrame: isClickFrame
            ) else {
                drop()
                return
            }

            self.encodeAndProcess(image: frame.image, compressionQuality: options.captureCompressionQuality,
                                  properties: self.propertiesWithCaptureMetadata(properties, maskRects: frame.maskRects),
                                  callerIncrementedCounter: callerIncrementedCounter,
                                  completion: completion)
        }
    }

    /// Epoch-milliseconds timestamp of the tap that triggered this capture, so Dart can drop a
    /// click frame that would land too long after the tap. `nil` for periodic captures.
    ///
    /// `getTimestamp` returns SECONDS on the capture path — `SessionReplay.captureEvent` stores
    /// `Date().timeIntervalSince1970` — and callers convert, the same way `handleCapturedData`
    /// hands its value to `SRNetworkManager` as `timestamp.milliseconds`. Sending seconds would
    /// make every tap read as hours stale, so Dart would drop every click frame.
    ///
    /// `Int64(exactly:)` rather than a trapping conversion: the value is read out of an untyped
    /// properties dictionary that hybrid bridges also populate, and a NaN or out-of-range Double
    /// must never crash the host app. `nil` omits the staleness check, which is already how a
    /// capture with no tap timestamp behaves.
    internal func tapTimestampMilliseconds(from properties: [String: Any]?, isClick: Bool) -> Int64? {
        guard isClick else { return nil }
        return Int64(exactly: (getTimestamp(from: properties) * 1_000).rounded())
    }

    // Returns the frame to composite, or nil to drop the whole capture.
    //
    // Nothing is ever carried across capture cycles: a nil delivery, a bitmap that fails to
    // decode, and a late out-of-order delivery all return nil. Substituting an earlier frame
    // would ship stale pixels under a fresh timestamp, and for a tap it would test marker
    // suppression against the wrong frame's mask rects — a marker over a field that is masked
    // now but was not masked then. Android drops on the same terms; see
    // `composeFlutterRegionOrDrop` in its FrameCapturer.
    internal func resolveFlutterFrame(freshBitmap: FlutterViewBitmap?, frameId: Int64) -> FlutterFrame? {
        // Decode outside the lock (cheap — no pixel copy).
        guard let bitmap = freshBitmap, let image = Self.makeCGImage(from: bitmap) else { return nil }
        let frame = FlutterFrame(image: image, maskRects: bitmap.maskRects)
        return flutterFrameQueue.sync {
            guard frameId > _latestAcceptedFlutterFrameId else { return nil }
            _latestAcceptedFlutterFrameId = frameId
            return frame
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

    /// True when any visible window in the active scene contains a SwiftUI
    /// hosting view. Must be called on the main thread at capture time —
    /// returns false otherwise. The result flows with the capture properties
    /// into `URLEntry.containsSwiftUIContent` (same pattern as the click point).
    internal func detectSwiftUIContentOnMain() -> Bool {
        guard Thread.isMainThread else { return false }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return false }

        return scene.windows
            .filter { !$0.isHidden && $0.alpha > 0 }
            .contains { UIView.subtreeContainsSwiftUIHostingView($0) }
    }

    /// Merges the facts that are only knowable on the main thread at capture time — the
    /// SwiftUI-content flag and the frame's mask rects — into the capture properties so they
    /// reach `handleCapturedData` → `URLEntry`. Same channel the click point already travels on.
    private func propertiesWithCaptureMetadata(
        _ properties: [String: Any]?,
        maskRects: [CGRect]
    ) -> [String: Any] {
        var props = properties ?? [:]
        props[Keys.containsSwiftUIContent.rawValue] = detectSwiftUIContentOnMain()
        props[Keys.maskRects.rawValue] = maskRects
        return props
    }

    /// JPEG-encodes the captured image off the main thread, performs the
    /// skip-identical check, and saves to disk if the frame is new.
    internal func encodeAndProcess(
        image: UIImage,
        compressionQuality: CGFloat,
        properties: [String: Any]?,
        callerIncrementedCounter: Bool,
        completion: CaptureEventCompletion? = nil
    ) {
        encodingQueue.async { [weak self] in
            guard let self = self else {
                completion?(.failure(.captureFailed))
                return
            }

            // Nothing shipped: hand the caller's screenshot index back and say so, so no span
            // advertises a screenshot the backend never receives.
            let drop: () -> Void = {
                if callerIncrementedCounter {
                    SdkManager.shared.getCoralogixSdk()?.revertScreenshotCounter()
                }
                completion?(.failure(.skippingEvent))
            }

            guard let screenshotData = image.jpegData(compressionQuality: compressionQuality) else {
                drop()
                return
            }

            let isClickFrame = self.getClickPoint(from: properties) != nil
            let shouldSkip = !isClickFrame && self.screenshotDataQueue.sync { () -> Bool in
                if let prvData = self._prvScreenshotData,
                   !self.imagesAreDifferent(screenshotData, prvData) {
                    return true
                }
                self._prvScreenshotData = screenshotData
                return false
            }

            if shouldSkip {
                drop()
                return
            }

            self.saveScreenshotToFileSystem(screenshotData: screenshotData, properties: properties)
            completion?(.success(()))
        }
    }

    internal func captureManual(properties: [String: Any]?, screenshotData: Data) {
        saveScreenshotToFileSystem(screenshotData: screenshotData, properties: properties)
    }

    internal func updateSessionId(with sessionId: String) {
        if sessionId != self.sessionId {
            self.sessionId = sessionId
            screenshotDataQueue.sync { _prvScreenshotData = nil }
            flutterFrameQueue.sync {
                _latestAcceptedFlutterFrameId = 0
                _flutterFrameGeneration &+= 1
            }
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
            let containsSwiftUIContent = (properties?[Keys.containsSwiftUIContent.rawValue] as? Bool) ?? false
            let maskRects = (properties?[Keys.maskRects.rawValue] as? [CGRect]) ?? []

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
                                    containsSwiftUIContent: containsSwiftUIContent,
                                    maskRects: maskRects,
                                    completion: completion)

            self.urlManager.addURL(urlEntry: urlEntry)
            self.updateSessionId(with: self.sessionId)
        }
    }

    internal func getClickPoint(from properties: [String: Any]?) -> CGPoint? {
        guard let properties = properties,
              let positionX = Self.coordinate(from: properties[Keys.positionX.rawValue]),
              let positionY = Self.coordinate(from: properties[Keys.positionY.rawValue]) else {
            return nil
        }
        return CGPoint(x: positionX, y: positionY)
    }

    /// Coerces a coordinate stored in the capture properties into a CGFloat.
    /// The value may arrive boxed as Double (production tap path), CGFloat, Int, or
    /// NSNumber. On iOS 26 a boxed `CGFloat as? Double` no longer succeeds, so each
    /// numeric representation is handled explicitly rather than relying on a single
    /// Double cast (BUGV2-6045).
    private static func coordinate(from value: Any?) -> CGFloat? {
        switch value {
        case let d as Double: return CGFloat(d)
        case let f as CGFloat: return f
        case let i as Int: return CGFloat(i)
        case let n as NSNumber: return CGFloat(truncating: n)
        default: return nil
        }
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
