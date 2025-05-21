//
//  UIViewExt.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 20/05/2025.
//

import UIKit

public extension UIView {
    func captureScreenshot(scale: CGFloat = UIScreen.main.scale,
                           compressionQuality: CGFloat = 0.8) -> Data? {
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = scale
        let renderer = UIGraphicsImageRenderer(bounds: self.bounds, format: rendererFormat)
        
        let image = renderer.image { context in
            self.drawHierarchy(in: self.bounds, afterScreenUpdates: false)
        }
        return image.jpegData(compressionQuality: compressionQuality)
    }
    
    func getKeyWindow() -> UIWindow? {
        guard let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }) // Filter only UIWindowScenes
            .flatMap({ $0.windows }) // Get all windows in each UIWindowScene
            .first(where: { $0.isKeyWindow }) // Find the key window
        else {
            Log.e("Unable to find the key window")
            return nil
        }
        return keyWindow
    }
}
