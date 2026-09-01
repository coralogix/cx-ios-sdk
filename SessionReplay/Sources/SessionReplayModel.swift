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
    private var _previousFingerprint: FrameFingerprint? = nil
    private let frameDiffOptions = FrameDiffOptions()

    /// Serial queue for off-main JPEG encoding. Serial so skip-identical comparison
    /// sees _previousFingerprint updates in capture order.
    internal let encodingQueue = DispatchQueue(
        label: "com.coralogix.sessionReplay.encodingQueue",
        qos: .userInitiated
    )

    /// Monotonic counter passed to flutterViewBitmapProvider as frameId. Guarded by
    /// `flutterFrameQueue`: `frameId` is the only admission gate a delivery passes, so two
    /// captures reading the same value would make one of them lose a perfectly good bitmap.
    private var _captureFrameCounter: Int64 = 0

    /// Reserves the next frameId.
    private func nextCaptureFrameId() -> Int64 {
        flutterFrameQueue.sync {
            _captureFrameCounter &+= 1
            return _captureFrameCounter
        }
    }

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

    /// What to do with one provider delivery. Three cases because the call site acts differently
    /// on each: only `composite` produces a frame, and only `staleSession` leaves the screenshot
    /// counter alone — after a rotation the index belongs to the new session, so handing it back
    /// would corrupt it.
    internal enum FlutterDeliveryOutcome {
        case composite(FlutterFrame)
        case staleSession
        case noFrame
    }

    /// How long a capture waits for Dart before giving up on the frame. Matches Android's
    /// FLUTTER_PROVIDER_TIMEOUT_MS. Unlike Android's, this timeout exists for the span rather
    /// than the frame: nothing here is blocked waiting, but a span cannot stay open forever.
    internal static let flutterProviderTimeout: TimeInterval = 1.0

    /// One-shot gate for a single provider delivery. Carries its own lock rather than borrowing
    /// `flutterFrameQueue`: the claim has to work before `self` is resolved, and a provider that
    /// breaks the main-thread contract must still not slip two deliveries past the check.
    internal final class FlutterDeliveryGate {
        private let lock = NSLock()
        private var isAnswered = false

        /// True for the first caller only.
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isAnswered else { return false }
            isAnswered = true
            return true
        }
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

    /// Reports a capture that produced no frame, and returns the screenshot slot the caller
    /// reserved for it.
    ///
    /// One definition on purpose: this used to be four near-copies, and the bug that started
    /// this branch was one of them being absent. The reservation is identified by the page and
    /// segment index the caller put in the properties, so returning it cannot roll back a newer
    /// capture's slot and make the next allocation overwrite a frame that already shipped.
    internal static func dropCapture(properties: [String: Any]?,
                                     completion: CaptureEventCompletion?,
                                     error: CaptureEventError = .skippingEvent) {
        if let page = properties?[Keys.page.rawValue] as? Int,
           let segmentIndex = properties?[Keys.segmentIndex.rawValue] as? Int {
            SdkManager.shared.getCoralogixSdk()?.revertScreenshotCounter(page: page,
                                                                        segmentIndex: segmentIndex)
        }
        completion?(.failure(error))
    }

    /// `completion` — when supplied — fires exactly once with the outcome the return value
    /// cannot carry: whether a frame was encoded and queued for upload. Both capture paths
    /// finish after this call returns (the native one encodes off-main, the Flutter one waits
    /// on Dart), so a caller that stamps a span with screenshot attributes must wait for it
    /// rather than trust `.success` here.
    ///
    /// Queued, not delivered: upload happens later and is retried out of band, well after a
    /// span has to close. The question a screenshot attribute asks is whether a frame exists
    /// for that index, and that is what this answers.
    internal func captureImage(properties: [String: Any]? = nil,
                               completion: CaptureEventCompletion? = nil) -> Result<Void, CaptureEventError> {
        guard !sessionId.isEmpty else {
            // startRecording fires the first periodic capture before update(sessionId:) may have
            // landed, so this is a routine early-session exit — and it burned a slot every time.
            Log.e("[SessionReplayModel] Invalid sessionId")
            Self.dropCapture(properties: properties, completion: nil)
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
        // Both paths walk UIKit before they do anything else: the native one renders the window
        // hierarchy, and the Flutter one locates the FlutterView before it asks Dart for pixels.
        // A capture requested off-main therefore used to fail those main-thread guards and drop
        // without ever requesting a frame — and captures do arrive off-main, an ANR span comes
        // from the watchdog thread and `reportError` can be called from anywhere. Hop instead,
        // the same way `prepareScreenshotIfNeeded` already does.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    completion?(.failure(.captureFailed))
                    return
                }
                _ = self.captureAutomatic(properties: properties, completion: completion)
            }
            return .success(())
        }

        // Flutter path: Dart rasterises + masks in one synchronous slice and pushes
        // the pre-masked bitmap to native. Async — returns immediately.
        if sessionReplayOptions?.flutterViewBitmapProvider != nil {
            captureAutomaticFlutter(properties: properties, completion: completion)
            return .success(())
        }

        // Native path: synchronous UIView walk on main thread, encode off-main.
        guard let frame = prepareCapturedFrameOnMain(properties: properties),
              let options = sessionReplayOptions else {
            Self.dropCapture(properties: properties, completion: nil)
            completion?(.failure(.captureFailed))
            return .failure(.captureFailed)
        }

        encodeAndProcess(
            image: frame.image,
            compressionQuality: options.captureCompressionQuality,
            properties: propertiesWithCaptureMetadata(properties, maskRects: frame.maskRects),
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

        let frameId = nextCaptureFrameId()
        let isClickFrame = getClickPoint(from: properties) != nil

        let isTap = isTapCapture(properties: properties)

        let drop: () -> Void = {
            // Deliberately not weak: the watchdog below has to be able to close the event out
            // after the model is gone, and dropCapture needs nothing from the instance.
            Self.dropCapture(properties: properties, completion: completion)
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
                             completion: completion)
            return
        }

        let requestGeneration = flutterFrameGeneration

        // The provider is host-app code (the Flutter plugin), so a second delivery for the
        // same cycle is possible; it must not composite twice or report the capture twice.
        let delivery = FlutterDeliveryGate()

        // Every span that carries a screenshot now closes in this capture's completion, so an
        // unanswered provider would stop error, log, tap and navigation events from being
        // exported at all — not just cost a frame — and pin each span in plugin-owned storage
        // with no ceiling. A wedged Dart isolate, a dropped MethodChannel reply or an engine
        // torn down mid-session all reach that state. Give up on the frame after a bounded wait
        // and let the span go; the gate makes a late reply harmless.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flutterProviderTimeout) {
            guard delivery.claim() else { return }
            Log.w("[SessionReplayModel] flutterViewBitmapProvider did not answer frameId \(frameId) within \(Self.flutterProviderTimeout)s — dropping the capture")
            drop()
        }

        // Everything the delivery does walks UIKit, so it has to run on main.
        let handleDelivery: (FlutterViewBitmap?) -> Void = { [weak self] bitmap in
            guard let self = self, let options = self.sessionReplayOptions else {
                drop()
                return
            }

            // nil = no frame for this cycle. Drop it — never black, never an earlier frame.
            // A delivery that outlived its session is dropped too, but keeps the screenshot
            // index: after a rotation that index belongs to the new session, so handing it back
            // would corrupt it. A one-index gap in the old session is the lesser evil.
            let flutterFrame: FlutterFrame
            switch self.acceptFlutterDelivery(freshBitmap: bitmap, frameId: frameId,
                                              requestGeneration: requestGeneration) {
            case .composite(let frame):
                flutterFrame = frame
            case .staleSession:
                // The index belongs to the new session now, so it is not ours to hand back.
                completion?(.failure(.skippingEvent))
                return
            case .noFrame:
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
                                  completion: completion)
        }

        // viewId is intentionally "implicit_view": the plugin ignores the argument and routes
        // every capture to Flutter's single implicit view, which is also the only view this path
        // composites. Only frameId matters.
        //
        // isClick/tapTimestampMs let Dart hold a tap capture for the next committed frame, or
        // answer nil when the tap is already too stale to draw honestly.
        provider("implicit_view", frameId, isTap,
                 tapTimestampMilliseconds(from: properties, isClick: isTap)) { bitmap in
            guard delivery.claim() else {
                Log.w("[SessionReplayModel] flutterViewBitmapProvider answered twice for frameId \(frameId) — ignoring")
                return
            }

            // A MethodChannel reply lands on whatever queue it likes, and a provider that hands
            // the bitmap over from a background queue has no reason to know better. Hop instead
            // of letting `prepareCapturedFrameOnMain`'s main-thread guard drop a good frame as if
            // Dart had sent nothing.
            guard Thread.isMainThread else {
                DispatchQueue.main.async { handleDelivery(bitmap) }
                return
            }
            handleDelivery(bitmap)
        }
    }

    /// JPEG-encodes a captured frame. Its own method so a test can fail the encode, which is the
    /// one path where a frame is compared, kept, and then still does not ship.
    internal func jpegData(from image: UIImage, compressionQuality: CGFloat) -> Data? {
        image.jpegData(compressionQuality: compressionQuality)
    }

    /// Whether this capture was triggered by a tap, as opposed to a scroll or a swipe.
    ///
    /// Distinct from `isClickFrame`, which asks "does this capture carry a touch position" — true
    /// of a scroll and a swipe too, since every interaction records coordinates. What the Flutter
    /// provider is told has to be narrower: hold this frame for a tap and judge it against the
    /// tap's age. A scroll has no single moment to be late for, so applying the One-Frame Rule
    /// and a staleness budget to one would drop frames for a gesture that never asked for either.
    internal func isTapCapture(properties: [String: Any]?) -> Bool {
        (properties?[Keys.eventName.rawValue] as? String) == InteractionEventName.click.rawValue
    }

    /// Epoch-milliseconds timestamp of the tap that triggered this capture, so Dart can drop a
    /// click frame that would land too long after the tap. `nil` for periodic captures, and for a
    /// click whose properties carry no timestamp — omitting the value skips the staleness check,
    /// which beats guessing at it.
    ///
    /// Reads `tapTimestamp`, the touch's own time, and not `timestamp` — every capture
    /// overwrites that one with its own wall clock in `SessionReplay.captureEvent`, so reading it
    /// here handed Dart the moment the capture started and a staleness delta of roughly zero, no
    /// matter how long the tap had actually been queued.
    ///
    /// `Int64(exactly:)` rather than a trapping conversion: the value is read out of an untyped
    /// properties dictionary that hybrid bridges also populate, and a NaN or out-of-range Double
    /// must never crash the host app.
    internal func tapTimestampMilliseconds(from properties: [String: Any]?, isClick: Bool) -> Int64? {
        guard isClick,
              let seconds = Self.seconds(from: properties?[Keys.tapTimestamp.rawValue]) else { return nil }
        return Int64(exactly: (seconds * 1_000).rounded())
    }

    /// Normalises a numeric value out of the untyped properties dictionary, the same way
    /// `coordinate(from:)` does for tap positions.
    ///
    /// `as? TimeInterval` alone is not enough: a caller writing an epoch value as an integer
    /// leaves a Swift `Int` in the box, which does not cast to `Double`, and the staleness budget
    /// would silently go missing for every tap that came in that way.
    ///
    /// A boolean has to be turned away before any numeric case runs, because Swift bridges one
    /// through `NSNumber` and `true as? Double` therefore succeeds as `1.0`. Left to run, a
    /// bridge that put a flag in this slot would date the tap a second after the epoch and Dart
    /// would decline every capture as impossibly stale — the opposite of the "no timestamp means
    /// skip the check" contract above. `CFBooleanGetTypeID` rather than `is Bool`, because an
    /// `NSNumber` holding 0 or 1 also satisfies `is Bool` and those are numbers.
    internal static func seconds(from value: Any?) -> TimeInterval? {
        guard let value, CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID() else { return nil }
        switch value {
        case let d as Double: return d
        case let i as Int: return TimeInterval(i)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    // Decides what to do with one delivery, in a single critical section.
    //
    // The session generation and the frameId watermark are tested together on purpose. Read
    // separately, `updateSessionId` can bump the generation and reset the watermark in the window
    // between the two reads, and a pre-rotation bitmap then passes both checks and is composited
    // into the new session — the exact leak the generation guard exists to prevent.
    //
    // Nothing is ever carried across capture cycles: a nil delivery, a bitmap that fails to
    // decode, and a late out-of-order delivery all yield `noFrame`. Substituting an earlier frame
    // would ship stale pixels under a fresh timestamp, and for a tap it would test marker
    // suppression against the wrong frame's mask rects — a marker over a field that is masked
    // now but was not masked then. Android drops on the same terms; see
    // `composeFlutterRegionOrDrop` in its FrameCapturer.
    //
    // The watermark rejects an out-of-order delivery on top of that, and the reason is delivery
    // order rather than metadata pairing. A late reply's pixels were rasterised when the reply
    // was made, not when its cycle was requested — so if cycle 8 answers before cycle 7, frame
    // 7's pixels show a *later* screen than frame 8's while carrying an *earlier* timestamp.
    // Shipping both makes the replay run backwards over that pair. Dropping the straggler costs
    // one rasterisation; keeping it corrupts the ordering the player depends on.
    internal func acceptFlutterDelivery(freshBitmap: FlutterViewBitmap?,
                                        frameId: Int64,
                                        requestGeneration: Int64) -> FlutterDeliveryOutcome {
        // Decode outside the lock (cheap — no pixel copy).
        let decoded = freshBitmap.flatMap { bitmap in
            Self.makeCGImage(from: bitmap).map { FlutterFrame(image: $0, maskRects: bitmap.maskRects) }
        }
        return flutterFrameQueue.sync {
            guard _flutterFrameGeneration == requestGeneration else { return .staleSession }
            guard let decoded, frameId > _latestAcceptedFlutterFrameId else { return .noFrame }
            _latestAcceptedFlutterFrameId = frameId
            return .composite(decoded)
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
        completion: CaptureEventCompletion? = nil
    ) {
        encodingQueue.async { [weak self] in
            guard let self = self else {
                // The model went away mid-encode; the slot still has to go back.
                Self.dropCapture(properties: properties, completion: completion)
                return
            }

            let drop: () -> Void = {
                Self.dropCapture(properties: properties, completion: completion)
            }

            // A manual capture is exempt from deduplication: the host asked for this frame, and
            // the void-returning public overload has no way to answer "identical to the last one".
            let isManual = (properties?[Keys.isManual.rawValue] as? Bool) == true

            // A click frame is exempt only when its marker will actually be drawn. The marker is
            // painted by the scanner pipeline downstream of here, so the image being compared
            // does not carry it yet and an unchanged screen would otherwise dedup the marker
            // frame away. But a tap inside a masked region is never drawn — the pipeline
            // suppresses it so a run of markers cannot reconstruct what was typed on a masked
            // keypad — and that frame is a true duplicate. Tested against the same rects the
            // pipeline will test, so the two cannot disagree.
            let clickPoint = self.getClickPoint(from: properties)
            let maskRects = (properties?[Keys.maskRects.rawValue] as? [CGRect]) ?? []
            let willDrawMarker = clickPoint.map { !maskRects.containsTap($0) } ?? false

            // Compared before encoding, so a dropped frame costs no JPEG. A frame whose
            // fingerprint cannot be built is kept: shipping it twice beats losing it.
            //
            // The comparison does not commit the baseline. Only a frame that reaches the save
            // path becomes what the next one is compared against — a frame whose encode fails
            // never shipped, and letting it set the baseline would silently skip the next
            // identical frame that could have.
            let fingerprint = image.cgImage.flatMap {
                FrameFingerprint.make(from: $0, options: self.frameDiffOptions)
            }
            let shouldSkip = !willDrawMarker && !isManual && self.screenshotDataQueue.sync {
                guard let fingerprint, let previous = self._previousFingerprint else { return false }
                return FrameSimilarity.isSame(previous, fingerprint, options: self.frameDiffOptions)
            }

            if shouldSkip {
                drop()
                return
            }

            guard let screenshotData = self.jpegData(from: image,
                                                     compressionQuality: compressionQuality) else {
                // Not a skip: the frame was wanted and the encode failed. Reported as such so a
                // caller — and anyone reading the logs — can tell a policy decision from a fault.
                Self.dropCapture(properties: properties, completion: completion, error: .captureFailed)
                return
            }

            if let fingerprint {
                self.screenshotDataQueue.sync { self._previousFingerprint = fingerprint }
            }
            self.saveScreenshotToFileSystem(screenshotData: screenshotData, properties: properties)
            completion?(.success(()))
        }
    }

    /// Ships a frame the caller encoded itself, bypassing the capture and comparison pipeline.
    ///
    /// Reached only by a host passing `Keys.screenshotData` to `captureEvent`; nothing inside the
    /// SDK does. The baseline still has to be released: this frame becomes the last one shipped,
    /// so leaving the previous automatic frame's fingerprint in place would measure the next
    /// automatic capture against a frame that is no longer what the replay last showed — and drop
    /// it as a duplicate when the screen had in fact changed twice.
    ///
    /// Cleared rather than replaced with this frame's own fingerprint. Decoding host-supplied data
    /// of unknown size on the capture path buys nothing: rendered by someone else, at their scale
    /// and quality, its fingerprint would not match our own capture of the same screen anyway, so
    /// the next frame ships either way. This is the file's standing trade — shipping one frame
    /// twice beats losing one.
    internal func captureManual(properties: [String: Any]?, screenshotData: Data) {
        screenshotDataQueue.sync { _previousFingerprint = nil }
        saveScreenshotToFileSystem(screenshotData: screenshotData, properties: properties)
    }

    internal func updateSessionId(with sessionId: String) {
        if sessionId != self.sessionId {
            self.sessionId = sessionId
            screenshotDataQueue.sync { _previousFingerprint = nil }
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

}
