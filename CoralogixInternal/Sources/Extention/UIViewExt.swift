//
//  UIViewExt.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 20/05/2025.
//

import UIKit

public extension UIView {
    func captureScreenshot(scale: CGFloat = 2.0,
                           compressionQuality: CGFloat = 0.8) -> Data? {
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = scale
        let renderer = UIGraphicsImageRenderer(bounds: self.bounds, format: rendererFormat)
        
        let image = renderer.image { context in
            self.drawHierarchy(in: self.bounds, afterScreenUpdates: false)
        }
        return image.jpegData(compressionQuality: compressionQuality)
    }
}
