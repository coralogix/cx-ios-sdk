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
    /// When true, this view will be masked (redacted).
    var cxMask: Bool {
        get { (objc_getAssociatedObject(self, &kCxMaskKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &kCxMaskKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// True when this view is masked, either directly or because an ancestor is.
    ///
    /// Masking is inherited: everything inside a masked view is masked, with no way to opt a
    /// descendant back out. This is what makes a tap on an unmasked key inside a masked keypad
    /// count as a tap on masked content — hit-testing resolves the key, which carries no masking
    /// signal of its own, so asking the key alone would report it unmasked.
    ///
    /// Resolved by walking up rather than by threading state down: the mask rects are collected
    /// from a live view hierarchy per capture, and the interaction path starts from an already
    /// hit-tested leaf, so there is no shared tree to seed.
    var isInsideMaskedSubtree: Bool {
        var view: UIView? = self
        while let current = view {
            if current.cxMask { return true }
            view = current.superview
        }
        return false
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

    /// Matches `text` against `patterns` as case-insensitive regex, falling back to a
    /// case-insensitive substring check for entries that aren't valid regex.
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

    /// Returns the whole `UINavigationBar` bounds (not the title's text frame) for each bar
    /// whose title matches `maskText`.
    ///
    /// During a push/pop UIKit draws the title with a snapshot layer that has no backing
    /// `UIView`, so the text-view walk can't redact it and the title leaks (iOS 18.5). The
    /// title string stays readable from `UINavigationItem`, so mask the bar's whole (stable)
    /// geometry instead of trying to locate the moving title.
    internal func collectMatchingNavigationBarRects(in rootView: UIView, maskText: [String]?) -> [CGRect] {
        guard let maskText = maskText, !maskText.isEmpty else { return [] }
        var rects: [CGRect] = []

        func traverse(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0 else { return }
            if let bar = view as? UINavigationBar {
                var titles = ([bar.topItem?.title, bar.backItem?.title]
                    .compactMap { $0 }) + (bar.items ?? []).compactMap { $0.title }
                #if os(iOS)
                if let prompt = bar.topItem?.prompt { titles.append(prompt) }
                #endif
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

    /// Every mask rect the native walk paints for one window — maskText matches,
    /// navigation-bar titles, maskAllImages, and `cxMask` views — offset to screen
    /// coordinates.
    ///
    /// The interaction path calls `deliberateMaskRects()`, which passes no text patterns and
    /// leaves `maskAllImages` off, so only `cxMask` views contribute.
    func collectNativeMaskRects(in win: UIWindow,
                                maskText: [String]?,
                                maskAllImages: Bool) -> [CGRect] {
        var rects: [CGRect] = []
        if let maskText = maskText, !maskText.isEmpty {
            rects += collectTextViewRects(in: win, maskText: maskText)
            rects += collectMatchingNavigationBarRects(in: win, maskText: maskText)
        }
        if maskAllImages {
            rects += collectImageViewRects(in: win)
        }
        rects += collectCxMaskRects(in: win)
        let origin = win.frame.origin
        return rects.map { $0.offsetBy(dx: origin.x, dy: origin.y) }
    }

    /// The mask rects for native content, across all visible windows of the active scene, in
    /// screen points. Windows hosting a FlutterView are skipped — their masking is reported by
    /// the wrapper rather than derivable from the view tree.
    ///
    /// Returns nil when there is nothing to walk (off the main thread, or no active
    /// foreground scene) — "don't know", which callers must not read as "nothing masked".
    /// An empty array means the walk ran and genuinely found no masked content.
    func collectScreenMaskRects(maskText: [String]?, maskAllImages: Bool) -> [CGRect]? {
        guard Thread.isMainThread, let scene = activeForegroundWindowScene() else { return nil }
        return collectMaskRects(in: scene.windows, maskText: maskText, maskAllImages: maskAllImages)
    }

    /// The windows-taking half of `collectScreenMaskRects`, split out so a caller that already
    /// holds a window list can reach the same walk — and so tests, which have no foreground
    /// scene to resolve, can exercise the real collection rather than re-deriving its inputs.
    func collectMaskRects(in windows: [UIWindow],
                          maskText: [String]?,
                          maskAllImages: Bool) -> [CGRect] {
        windows
            .filter { !$0.isHidden && $0.alpha > 0 && !UIView.subtreeContainsFlutterView($0) }
            .flatMap { collectNativeMaskRects(in: $0, maskText: maskText, maskAllImages: maskAllImages) }
    }

    /// The mask geometry the interaction path tests a tap against: deliberate masking only —
    /// `cxMask`, whether set directly, inherited from an ancestor, or applied to SwiftUI
    /// content via the `.cxMask()` overlay.
    ///
    /// Text patterns (`maskText`) and `maskAllImages` are deliberately absent: they answer
    /// "should these pixels be hidden", which is not the question "may this text leave the
    /// device". Android and Flutter resolve the verdict from deliberate masking alone; this
    /// matches them.
    ///
    /// The production path delegates to `collectScreenMaskRects`
    /// rather than restating its guards, so the conditions under which this returns nil are
    /// defined in one place and cannot drift as they are added to.
    /// - Parameter windows: Test seam. nil (production) resolves the active foreground scene;
    ///   passing a list walks those windows instead, so the policy-off inputs this function
    ///   chooses can be pinned by a test with no scene available.
    static func deliberateMaskRects(in windows: [UIWindow]? = nil) -> [CGRect]? {
        let view = UIView()
        guard let windows else {
            return view.collectScreenMaskRects(maskText: nil, maskAllImages: false)
        }
        return view.collectMaskRects(in: windows, maskText: nil, maskAllImages: false)
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
                // Deliberately keeps descending. Android's equivalent stops at a masked node
                // because masking is inherited there, so every descendant reports itself masked
                // and the walk would emit a rect per node. Here `cxMask` stays per-view, so a
                // descendant only contributes a rect when it was masked explicitly — and it must,
                // since subviews are not clipped to their parent and a masked child can extend
                // past a masked parent's bounds.
            }
            for subview in view.subviews {
                traverse(subview)
            }
        }

        traverse(rootView)
        return rects
    }
}
