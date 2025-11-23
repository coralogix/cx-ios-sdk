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

    func captureScreenshot(
        scale: CGFloat = UIScreen.main.scale,
        compressionQuality: CGFloat = 0.8,
        regions: [CGRect]? = nil
    ) -> Data? {
        guard Thread.isMainThread else {
            Log.e("captureScreenshot must be called on the main thread")
            return nil
        }

        guard let scene = activeForegroundWindowScene() else { return nil }

        let windows = scene.windows
            .filter { !$0.isHidden && $0.alpha > 0 }
            .sorted(by: { $0.windowLevel < $1.windowLevel })

        let bounds = scene.screen.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        let image = renderer.image { ctx in
            for win in windows {
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: win.frame.origin.x, y: win.frame.origin.y)
                if !win.drawHierarchy(in: win.bounds, afterScreenUpdates: true) {
                    win.layer.render(in: ctx.cgContext)
                }
                ctx.cgContext.restoreGState()
            }
        }

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
        
        if !allMaskRects.isEmpty {
            let redacted = applyCxMaskRects(allMaskRects, on: image, scale: scale)
            return redacted.jpegData(compressionQuality: compressionQuality)
        }
        return image.jpegData(compressionQuality: compressionQuality)
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
    
    func applyCxMaskRects(_ rects: [CGRect], on image: UIImage, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { ctx in
            image.draw(at: .zero)
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            for rect in rects {
                ctx.cgContext.fill(rect)
            }
        }
    }
}
