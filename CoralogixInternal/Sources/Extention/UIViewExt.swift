//
//  UIViewExt.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 20/05/2025.
//

import UIKit
import ObjectiveC

private var kCxMaskKey: UInt8 = 0

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

    /// Renders a screenshot of the active window scene with all `cxMask` views and
    /// any rectangles passed via `regions` blacked out, in a single
    /// `UIGraphicsImageRenderer` pass. Must be called on the main thread.
    /// JPEG encoding is intentionally NOT performed here — callers can encode
    /// off-main since `UIImage`/`CGImage` are not main-thread bound.
    func captureScreenshotImage(
        scale: CGFloat = UIScreen.main.scale,
        regions: [CGRect]? = nil
    ) -> UIImage? {
        guard Thread.isMainThread else {
            Log.e("captureScreenshotImage must be called on the main thread")
            return nil
        }

        guard let scene = activeForegroundWindowScene() else { return nil }

        let windows = scene.windows
            .filter { !$0.isHidden && $0.alpha > 0 }
            .sorted(by: { $0.windowLevel < $1.windowLevel })

        var allMaskRects: [CGRect] = []
        for window in windows {
            let rects = collectCxMaskRects(in: window).map {
                $0.offsetBy(dx: window.frame.origin.x, dy: window.frame.origin.y)
            }
            allMaskRects.append(contentsOf: rects)
        }
        if let regions = regions, !regions.isEmpty {
            allMaskRects.append(contentsOf: regions)
        }

        let bounds = scene.screen.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        return renderer.image { ctx in
            for win in windows {
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: win.frame.origin.x, y: win.frame.origin.y)
                if !win.drawHierarchy(in: win.bounds, afterScreenUpdates: false) {
                    win.layer.render(in: ctx.cgContext)
                }
                ctx.cgContext.restoreGState()
            }
            if !allMaskRects.isEmpty {
                ctx.cgContext.setFillColor(UIColor.black.cgColor)
                for rect in allMaskRects {
                    ctx.cgContext.fill(rect)
                }
            }
        }
    }

    /// Synchronous wrapper that captures the image and JPEG-encodes inline.
    /// Hot paths should call `captureScreenshotImage` and encode off-main instead.
    func captureScreenshot(
        scale: CGFloat = UIScreen.main.scale,
        compressionQuality: CGFloat = 0.8,
        regions: [CGRect]? = nil
    ) -> Data? {
        return captureScreenshotImage(scale: scale, regions: regions)?
            .jpegData(compressionQuality: compressionQuality)
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
