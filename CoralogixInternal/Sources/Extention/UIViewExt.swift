//
//  UIViewExt.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 20/05/2025.
//

import UIKit

public extension UIView {
    func activeForegroundWindowScene() -> UIWindowScene? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    func captureScreenshot(
        scale: CGFloat = UIScreen.main.scale,
        compressionQuality: CGFloat = 0.8
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

        return image.jpegData(compressionQuality: compressionQuality)
    }
}
