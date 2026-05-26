//
//  UIViewExt.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 20/05/2025.
//

import UIKit
import ObjectiveC

private var kCxMaskKey: UInt8 = 0

// Resolved once; safe when Flutter is not on the classpath.
private let _flutterViewClass: AnyClass? =
    NSClassFromString("FlutterView")
    ?? NSClassFromString("FlutterSurfaceView")
    ?? NSClassFromString("FlutterImageView")

public extension UIView {
    /// When true, this view will be masked (redacted) in captured session frames.
    var cxMask: Bool {
        get { (objc_getAssociatedObject(self, &kCxMaskKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &kCxMaskKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func activeForegroundWindowScene() -> UIWindowScene? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    // MARK: - FlutterView detection

    /// Returns true when any view in the subtree is a FlutterView (or surface/image variant).
    /// Safe to call when Flutter is not on the classpath — returns false.
    static func subtreeContainsFlutterView(_ view: UIView) -> Bool {
        guard let cls = _flutterViewClass else { return false }
        if view.isKind(of: cls) { return true }
        for sub in view.subviews where subtreeContainsFlutterView(sub) { return true }
        return false
    }

    /// Depth-first search for the first FlutterView in a subtree. Returns nil when not found.
    static func findFlutterViewInSubtree(_ view: UIView) -> UIView? {
        guard let cls = _flutterViewClass else { return nil }
        if view.isKind(of: cls) { return view }
        for sub in view.subviews {
            if let found = findFlutterViewInSubtree(sub) { return found }
        }
        return nil
    }

    // MARK: - UIView-walk mask collectors

    /// Collects rects for text-bearing views (UILabel, UITextField, UITextView) in `rootView`'s
    /// coordinate space. Short-circuits at FlutterView subtrees — those arrive pre-masked
    /// via the Dart bitmap provider.
    func collectTextViewRects(in rootView: UIView, maskAllTexts: Bool, textsToMask: [String]) -> [CGRect] {
        var rects: [CGRect] = []

        func traverse(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0 else { return }
            if let cls = _flutterViewClass, view.isKind(of: cls) { return }

            var shouldMask = false
            if maskAllTexts {
                shouldMask = view is UILabel || view is UITextField || view is UITextView
            } else if !textsToMask.isEmpty {
                if let label = view as? UILabel, let text = label.text {
                    shouldMask = textsToMask.contains { text.localizedCaseInsensitiveContains($0) }
                } else if let field = view as? UITextField, let text = field.text {
                    shouldMask = textsToMask.contains { text.localizedCaseInsensitiveContains($0) }
                } else if let tv = view as? UITextView, let text = tv.text {
                    shouldMask = textsToMask.contains { text.localizedCaseInsensitiveContains($0) }
                }
            }

            if shouldMask {
                let rect = view.convert(view.bounds, to: rootView).intersection(rootView.bounds)
                if !rect.isNull && !rect.isEmpty { rects.append(rect) }
            }

            for sub in view.subviews { traverse(sub) }
        }

        traverse(rootView)
        return rects
    }

    /// Collects rects for UIImageView instances in `rootView`'s coordinate space.
    /// Short-circuits at FlutterView subtrees.
    func collectImageViewRects(in rootView: UIView) -> [CGRect] {
        var rects: [CGRect] = []

        func traverse(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0 else { return }
            if let cls = _flutterViewClass, view.isKind(of: cls) { return }

            if view is UIImageView {
                let rect = view.convert(view.bounds, to: rootView).intersection(rootView.bounds)
                if !rect.isNull && !rect.isEmpty { rects.append(rect) }
            }

            for sub in view.subviews { traverse(sub) }
        }

        traverse(rootView)
        return rects
    }

    // MARK: - Screenshot capture

    /// Renders a composite screenshot of all visible windows with masking applied.
    ///
    /// Per-window routing:
    /// - Windows whose subtree contains a FlutterView → composite `flutterCGImage` at
    ///   `flutterViewRect`; if either is nil → black fill.
    /// - All other windows → `drawHierarchy(afterScreenUpdates:false)` + synchronous UIView
    ///   walks for text, image, and `cxMask` views.
    ///
    /// Must be called on the main thread.
    func captureScreenshotImage(
        scale: CGFloat = UIScreen.main.scale,
        maskAllTexts: Bool = false,
        textsToMask: [String] = [],
        maskAllImages: Bool = false,
        flutterCGImage: CGImage? = nil,
        flutterViewRect: CGRect? = nil
    ) -> UIImage? {
        guard Thread.isMainThread else {
            Log.e("captureScreenshotImage must be called on the main thread")
            return nil
        }

        guard let scene = activeForegroundWindowScene() else { return nil }

        let windows = scene.windows
            .filter { !$0.isHidden && $0.alpha > 0 }
            .sorted(by: { $0.windowLevel < $1.windowLevel })

        var nativeMaskRects: [CGRect] = []
        let bounds = scene.screen.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        return renderer.image { _ in
            for win in windows {
                if UIView.subtreeContainsFlutterView(win) {
                    // Flutter window: paste Dart pre-masked bitmap; black-fill on nil/missing rect.
                    // Never fall through to win.layer.render — GPU surfaces produce transparent holes.
                    if let rect = flutterViewRect, let cgImage = flutterCGImage {
                        let uiImage = UIImage(cgImage: cgImage,
                                              scale: UIScreen.main.scale,
                                              orientation: .up)
                        uiImage.draw(in: rect)
                    } else {
                        UIColor.black.setFill()
                        UIRectFill(flutterViewRect ?? win.bounds)
                    }
                } else {
                    // Native window: render from the model layer so that mask-rect
                    // collection (which also reads model-layer positions via
                    // view.convert) stays in the same coordinate frame.
                    // drawHierarchy captures the presentation layer, which diverges
                    // from the model layer during scroll animations and causes
                    // mask-position skew (BUGV2-6045).
                    let origin = win.frame.origin
                    let ctx = UIGraphicsGetCurrentContext()!
                    ctx.saveGState()
                    ctx.translateBy(x: origin.x, y: origin.y)
                    win.layer.render(in: ctx)
                    ctx.restoreGState()

                    if maskAllTexts || !textsToMask.isEmpty {
                        nativeMaskRects += collectTextViewRects(in: win,
                                                                maskAllTexts: maskAllTexts,
                                                                textsToMask: textsToMask)
                            .map { $0.offsetBy(dx: origin.x, dy: origin.y) }
                    }
                    if maskAllImages {
                        nativeMaskRects += collectImageViewRects(in: win)
                            .map { $0.offsetBy(dx: origin.x, dy: origin.y) }
                    }
                    nativeMaskRects += collectCxMaskRects(in: win)
                        .map { $0.offsetBy(dx: origin.x, dy: origin.y) }
                }
            }

            if !nativeMaskRects.isEmpty {
                UIColor.black.setFill()
                for rect in nativeMaskRects { UIRectFill(rect) }
            }
        }
    }

    /// Convenience wrapper — captures and JPEG-encodes inline. Prefer calling
    /// `captureScreenshotImage` and encoding off-main on hot paths.
    func captureScreenshot(
        scale: CGFloat = UIScreen.main.scale,
        compressionQuality: CGFloat = 0.8
    ) -> Data? {
        return captureScreenshotImage(scale: scale)?.jpegData(compressionQuality: compressionQuality)
    }

    func collectCxMaskRects(in rootView: UIView) -> [CGRect] {
        var rects: [CGRect] = []

        func traverse(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0 else { return }

            if view.cxMask {
                var rect = view.convert(view.bounds, to: rootView)
                rect = rect.intersection(rootView.bounds)
                if !rect.isNull && !rect.isEmpty {
                    rects.append(rect)
                }
            }
            for subview in view.subviews {
                traverse(subview)
            }
        }

        traverse(rootView)
        return rects
    }
}
