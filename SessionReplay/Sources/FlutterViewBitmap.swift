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

    public init?(bytes: Data, width: Int, height: Int) {
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
    }
}

/// Callback signature used by [SessionReplayOptions.flutterViewBitmapProvider].
///
/// Invoked by the SDK per FlutterView per capture cycle. `viewId` is the
/// Flutter-allocated stable identifier (format `cx_flutter_view_<counter>`,
/// see `docs/session-replay-shared.md` §3). `frameId` is a monotonic
/// SDK-generated counter (see §2 — opaque to the provider; do not
/// interpret as a timestamp).
///
/// The completion handler must be called with the bytes, or `nil` if the
/// FlutterView isn't ready yet. On `nil` the SDK reuses the last delivered
/// bitmap, or skips the frame if none has arrived — never black, and never
/// the raw FlutterView pixels (the leak case).
public typealias FlutterViewBitmapProvider =
    (_ viewId: String, _ frameId: Int64,
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
