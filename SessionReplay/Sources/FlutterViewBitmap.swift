// FlutterViewBitmap.swift
//
// Type stubs for the Flutter bitmap-provider contract (BUGV2-6045).
// Additive in this release — wiring lives in the cx-flutter-plugin
// repo; this pod only declares the surface the plugin registers against.
//
// Full cross-platform pixel-format ABI, frame-id semantics, and viewId
// scheme are normative in `docs/session-replay-shared.md` in the
// cx-flutter-plugin repo. Behaviour-side integration plan in
// `docs/session-replay-ios.md` §4.2.

import Foundation
import CoralogixInternal

/// A pre-masked RGBA8888 bitmap supplied by the Flutter plugin for a
/// single FlutterView found in the captured view hierarchy.
///
/// The Flutter plugin (`cx-flutter-plugin`) rasterises the Flutter
/// widget tree and composites all mask rectangles into the returned
/// bytes in one synchronous slice, so the pixel data and the mask
/// placement are guaranteed to reference the same frame. The iOS SDK
/// substitutes these bytes into the FlutterView region of its captured
/// host bitmap, replacing the masking pipeline's pull-based rect
/// handoff (which is subject to frame-skew during scroll/animation).
///
/// `bytes` is RGBA8888 premultiplied alpha, big-endian within pixel
/// (R, G, B, A in order), `width * 4` bytes per row, no row padding,
/// total length `width * height * 4`. It is consumed by
/// `CGDataProvider` + `CGImage` with `CGImageAlphaInfo.premultipliedLast`
/// — see `docs/session-replay-shared.md` §1 for the iOS receiving-side
/// snippet.
///
/// Any change here must be mirrored in the Android
/// `FlutterViewBitmap` data class and the Dart `MaskedFrameBytes` class.
public struct FlutterViewBitmap {
    /// RGBA8888 premul, exactly `width * height * 4` bytes.
    public let bytes: Data
    /// Pixel width.
    public let width: Int
    /// Pixel height.
    public let height: Int
    /// The rectangles Dart masked in `bytes`, in Flutter-view-local logical points (Dart's
    /// logical pixels are UIKit points — no unit conversion on iOS, unlike Android where the
    /// payload is dp and the host rects are px). The host offsets them by the FlutterView's
    /// screen origin and merges them into `CapturedFrame.maskRects`, so tap markers over
    /// masked Flutter content are suppressed on the same terms as native masks. They travel
    /// with the bytes, so the geometry and the pixels it describes always reference the same
    /// frame by construction.
    public let maskRects: [CGRect]

    public init?(bytes: Data, width: Int, height: Int, maskRects: [CGRect] = []) {
        guard width > 0 && height > 0 else {
            Log.w("FlutterViewBitmap: invalid dimensions \(width)x\(height) — treating as missing bitmap")
            return nil
        }
        // width/height arrive from the Flutter plugin (untrusted cross-boundary data);
        // Swift traps on signed-integer overflow, so compute the byte count with
        // overflow-reporting math and treat any overflow as a missing bitmap rather
        // than crashing the host app.
        let (pixels, pixelsOverflow)  = width.multipliedReportingOverflow(by: height)
        let (expected, bytesOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !pixelsOverflow, !bytesOverflow else {
            Log.w("FlutterViewBitmap: dimensions \(width)x\(height) overflow — treating as missing bitmap")
            return nil
        }
        guard bytes.count == expected else {
            Log.w("FlutterViewBitmap: byte count \(bytes.count) ≠ \(width)×\(height)×4 — treating as missing bitmap")
            return nil
        }
        self.bytes = bytes
        self.width = width
        self.height = height
        self.maskRects = maskRects
    }
}

/// Callback signature used by [SessionReplayOptions.flutterViewBitmapProvider].
///
/// Invoked once per capture cycle, for Flutter's implicit view.
///
/// - `viewId`: always `"implicit_view"`. The SDK composites one FlutterView per capture —
///   the first it finds on screen — and the plugin routes every capture to Flutter's single
///   implicit view, so the argument carries no information today. A host with several
///   FlutterViews is not supported by this path.
/// - `frameId`: a monotonic SDK counter. Opaque — not a timestamp.
/// - `isClick`: this capture was triggered by a user tap.
/// - `tapTimestampMs`: that tap's epoch-ms timestamp, `nil` for periodic captures.
///
/// Call the completion exactly once, with the bytes or with `nil`. `nil` means "no frame
/// for this cycle", whatever the reason, and the SDK drops the capture: never a black
/// fill, never the raw FlutterView pixels, never a frame from an earlier cycle. A second
/// call for the same cycle is ignored.
///
/// The completion may be called from any thread; the SDK moves the work to the main thread
/// itself. Answer within one second: the capture gives up after that and reports the event
/// without a screenshot. The cap is there because the event's own span closes when the capture
/// resolves, so an unanswered provider would hold back error, log, tap and navigation events
/// rather than merely cost a frame. A late answer is ignored, not composited.
public typealias FlutterViewBitmapProvider =
    (_ viewId: String, _ frameId: Int64, _ isClick: Bool, _ tapTimestampMs: Int64?,
     _ completion: @escaping (FlutterViewBitmap?) -> Void) -> Void

/// Callback signature used by [SessionReplayOptions.flutterPlatformViewsProvider].
///
/// Returns the list of currently-registered Flutter platform-view IDs
/// for the given FlutterView. Used by the iOS capture pipeline to
/// re-paint platform views (Maps, WebView, etc.) on top of the Dart
/// bitmap after substitution. See `docs/session-replay-ios.md` §4.3
/// for the composition order.
public typealias FlutterPlatformViewsProvider =
    (_ viewId: String,
     _ completion: @escaping ([Int64]) -> Void) -> Void
