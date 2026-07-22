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

    // MARK: - SwiftUI hosting-view detection

    /// True when any view in the subtree is a SwiftUI hosting view.
    /// Class-name string matching (no NSClassFromString — avoids +initialize side
    /// effects; see Sentry's SentryUIRedactBuilder for precedent). The mangled
    /// name of SwiftUI's hosting view (`_TtGC7SwiftUI14_UIHostingView…`) contains
    /// "UIHostingView" for both root hosting views in pure-SwiftUI apps and
    /// `UIHostingController` embeddings in hybrid apps.
    /// Short-circuits at FlutterView subtrees — those arrive pre-masked.
    static func subtreeContainsSwiftUIHostingView(_ view: UIView) -> Bool {
        if let cls = _flutterViewClass, view.isKind(of: cls) { return false }
        if NSStringFromClass(type(of: view)).contains("UIHostingView") { return true }
        for sub in view.subviews where subtreeContainsSwiftUIHostingView(sub) { return true }
        return false
    }

    // MARK: - UIView-walk mask collectors

    /// Returns the view's rect in rootView's coordinate space using the
    /// presentation layer position at every level of the hierarchy.
    ///
    /// drawHierarchy captures the compositor frame (presentation layer positions).
    /// A single-step superlayer.convert(…, to: rootView.layer) only reads the
    /// presentation layer of the leaf view; any ancestor that is mid-animation
    /// (e.g. the entire VC view during a navigation push/pop) is still read at
    /// its model position, causing mask skew (BUGV2-6045).
    ///
    /// Walking one superview at a time and using presentation() ?? layer at
    /// each hop ensures the full animated coordinate chain is reflected.
    private func presentationRect(of view: UIView, in rootView: UIView) -> CGRect {
        var rect = view.bounds
        var cur  = view
        while cur !== rootView {
            guard let parent = cur.superview else {
                return view.convert(view.bounds, to: rootView).intersection(rootView.bounds)
            }
            let from = cur.layer.presentation()    ?? cur.layer
            let to   = parent.layer.presentation() ?? parent.layer
            rect = from.convert(rect, to: to)
            cur  = parent
        }
        return rect.intersection(rootView.bounds)
    }

    /// True when `text` matches any entry in `patterns`. Each entry is treated as a
    /// case-insensitive regular expression, falling back to a case-insensitive substring
    /// match when the entry is not valid regex.
    internal static func textMatchesAny(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return text.localizedCaseInsensitiveContains(pattern)
            }
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    /// Collects rects for text-bearing views (UILabel, UITextField, UITextView) in `rootView`'s
    /// coordinate space. Short-circuits at FlutterView subtrees — those arrive pre-masked
    /// via the Dart bitmap provider.
    func collectTextViewRects(in rootView: UIView, maskText: [String]?) -> [CGRect] {
        var rects: [CGRect] = []
        guard let maskText = maskText, !maskText.isEmpty else { return rects }

        func traverse(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0 else { return }
            if let cls = _flutterViewClass, view.isKind(of: cls) { return }

            var shouldMask = false
            if let label = view as? UILabel, let text = label.text {
                shouldMask = UIView.textMatchesAny(text, maskText)
            } else if let field = view as? UITextField, let text = field.text {
                shouldMask = UIView.textMatchesAny(text, maskText)
            } else if let tv = view as? UITextView, let text = tv.text {
                shouldMask = UIView.textMatchesAny(text, maskText)
            }

            if shouldMask {
                let rect = presentationRect(of: view, in: rootView)
                if !rect.isNull && !rect.isEmpty { rects.append(rect) }
            }

            for sub in view.subviews { traverse(sub) }
        }

        traverse(rootView)
        return rects
    }

    /// Collects a mask rect for any visible `UINavigationBar` whose title text matches
    /// `maskText`.
    ///
    /// During a push/pop UIKit renders the navigation-bar title with a snapshot *layer* that
    /// has no backing `UIView`, so the text-view walk above can't redact it and the title
    /// leaks for the frames the transition guard misses (iOS 18.5; iOS 26 composites the
    /// title in place, so it never leaks there). The bar's own frame is stable through the
    /// transition, and the title string is readable from `UINavigationItem` regardless of how
    /// it is being composited, so mask the whole bar by geometry when its title matches.
    /// Scoped to bars whose title actually matches `maskText`, so unrelated bars are untouched.
    internal func collectNavigationBarTitleRects(in rootView: UIView, maskText: [String]?) -> [CGRect] {
        guard let maskText = maskText, !maskText.isEmpty else { return [] }
        var rects: [CGRect] = []

        func traverse(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0 else { return }
            if let bar = view as? UINavigationBar {
                let titles = ([bar.topItem?.title, bar.topItem?.prompt, bar.backItem?.title]
                    .compactMap { $0 }) + (bar.items ?? []).compactMap { $0.title }
                if titles.contains(where: { UIView.textMatchesAny($0, maskText) }) {
                    let rect = bar.convert(bar.bounds, to: rootView).intersection(rootView.bounds)
                    if !rect.isNull && !rect.isEmpty { rects.append(rect) }
                }
                return
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
                let rect = presentationRect(of: view, in: rootView)
                if !rect.isNull && !rect.isEmpty { rects.append(rect) }
            }

            for sub in view.subviews { traverse(sub) }
        }

        traverse(rootView)
        return rects
    }

    // MARK: - Screenshot capture

    /// Returns true when a screenshot taken right now would mask at the wrong place because
    /// view-controller content in the active scene is mid-transition.
    ///
    /// Two complementary signals — a frame is unsafe if either fires:
    /// - `transitionCoordinator != nil` catches a transition's leading edge, where the
    ///   coordinator is set before the compositor has moved anything.
    /// - Composited-vs-model displacement of a view-controller's view catches the trailing
    ///   edge: the coordinator clears a frame or two before the slide finishes settling, and
    ///   the mask-rect walk lands off the still-moving content, leaking a sliver.
    ///
    /// (The navigation-bar *title* leak is handled separately, by masking the bar's geometry
    /// in `collectNavigationBarTitleRects` — its snapshot layer can't be caught here.)
    static func isNavigationTransitionActive() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return false }
        return scene.windows.contains { win in
            guard let root = win.rootViewController else { return false }
            return Self.vcHasActiveTransition(root) || Self.vcContentIsDisplaced(root, in: win)
        }
    }

    private static func vcHasActiveTransition(_ vc: UIViewController) -> Bool {
        if vc.transitionCoordinator != nil { return true }
        for child in vc.children where vcHasActiveTransition(child) { return true }
        if let presented = vc.presentedViewController, vcHasActiveTransition(presented) { return true }
        return false
    }

    /// True when a loaded view controller's view is composited away from its model position
    /// in `window` — i.e. mid-slide. Walks only view-controller views (one layer per VC),
    /// so ordinary in-content animations don't trip it. `viewIfLoaded` avoids forcing
    /// `loadView` during capture.
    private static func vcContentIsDisplaced(_ vc: UIViewController, in window: UIWindow) -> Bool {
        if let view = vc.viewIfLoaded, view.window === window, Self.isDisplaced(view, in: window) {
            return true
        }
        for child in vc.children where vcContentIsDisplaced(child, in: window) { return true }
        if let presented = vc.presentedViewController, vcContentIsDisplaced(presented, in: window) {
            return true
        }
        return false
    }

    /// True when `view`'s composited (presentation) origin diverges from its model origin in
    /// `root` coordinates. Must run on the main thread outside a render pass, where
    /// `presentation()` reflects the in-flight animated values.
    private static func isDisplaced(_ view: UIView, in root: UIView, epsilon: CGFloat = 0.5) -> Bool {
        var point = CGPoint.zero
        var cur: UIView = view
        while cur !== root {
            guard let parent = cur.superview else { break }
            let from = cur.layer.presentation() ?? cur.layer
            let to = parent.layer.presentation() ?? parent.layer
            point = from.convert(point, to: to)
            cur = parent
        }
        let model = view.convert(CGPoint.zero, to: root)
        return abs(point.x - model.x) > epsilon || abs(point.y - model.y) > epsilon
    }

    /// Renders a composite screenshot of all visible windows with masking applied.
    ///
    /// Per-window routing:
    /// - Windows whose subtree contains a FlutterView → composite `flutterCGImage` at
    ///   `flutterViewRect`; if either is nil → black fill.
    /// - All other windows → `drawHierarchy(afterScreenUpdates:false)` + synchronous UIView
    ///   walks for text, image, and `cxMask` views.
    ///
    /// Returns nil (skipped) when a navigation transition is in progress — see
    /// `isNavigationTransitionActive()`.
    ///
    /// Must be called on the main thread.
    func captureScreenshotImage(
        scale: CGFloat = UIScreen.main.scale,
        maskText: [String]? = nil,
        maskAllImages: Bool = false,
        flutterCGImage: CGImage? = nil,
        flutterViewRect: CGRect? = nil,
        isClickFrame: Bool = false
    ) -> UIImage? {
        guard Thread.isMainThread else {
            Log.e("captureScreenshotImage must be called on the main thread")
            return nil
        }

        guard isClickFrame || !UIView.isNavigationTransitionActive() else {
            Log.d("[SR] skipping capture — navigation transition in progress")
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

        return renderer.image { rendererContext in
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
                        // Screen-space fallback: flutterViewRect is already in screen
                        // coordinates (flutterView.convert(_, to: nil)); win.frame matches
                        // the renderer's screen-coordinate space, win.bounds (origin 0,0)
                        // would black-fill the wrong spot for an offset window (BUGV2-6045).
                        UIColor.black.setFill()
                        UIRectFill(flutterViewRect ?? win.frame)
                    }
                } else {
                    // Native window: drawHierarchy goes through the screen compositor
                    // and captures GPU-composited content (scrolled cells, etc.)
                    // correctly. layer.render only sees CPU-backed layer content and
                    // produces white output for GPU-composited views — do not use it
                    // as the primary renderer.
                    let origin = win.frame.origin
                    let ctx = rendererContext.cgContext
                    ctx.saveGState()
                    ctx.translateBy(x: origin.x, y: origin.y)
                    if !win.drawHierarchy(in: win.bounds, afterScreenUpdates: false) {
                        win.layer.render(in: ctx)
                    }
                    ctx.restoreGState()

                    if let maskText = maskText, !maskText.isEmpty {
                        nativeMaskRects += collectTextViewRects(in: win, maskText: maskText)
                            .map { $0.offsetBy(dx: origin.x, dy: origin.y) }
                        nativeMaskRects += collectNavigationBarTitleRects(in: win, maskText: maskText)
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
                let rect = presentationRect(of: view, in: rootView)
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
