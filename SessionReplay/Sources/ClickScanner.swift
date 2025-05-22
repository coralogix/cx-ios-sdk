//
//  ClickScanner.swift
//  
//
//  Created by Tomer Har Yoffi on 26/01/2025.
//

import UIKit
import CoreImage
import CoralogixInternal

class ClickScanner {
    
    // Function to process the image, detect clicks, and add them to the image
    func processImage(at ciImage: CIImage,
                      x: CGFloat,
                      y: CGFloat,
                      completion: @escaping (CIImage?) -> Void) {
        let screenSize = UIScreen.main.bounds.size
        let imageSize = ciImage.extent.size
        
        // Scale screen point to image pixels
        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height
        
        let scaledX = x * scaleX
        let scaledY = y * scaleY
        let flippedY = imageSize.height - scaledY
        let imagePoint = CGPoint(x: scaledX, y: flippedY)
        
        guard let clickedCGImage = self.addClickMark(to: ciImage, at: imagePoint.x, y: imagePoint.y) else {
            completion(nil)
            return
        }
        completion(clickedCGImage)
    }
    
    // Function to add a programmatically created click mark to a CIImage
    func addClickMark(to ciImage: CIImage,
                      at x: CGFloat,
                      y: CGFloat,
                      markSize: CGSize = CGSize(width: 50, height: 50)) -> CIImage? {
        // Create a CIContext
        let context = CIContext()

        // Convert the CIImage to a CGImage
        guard let baseCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            Log.e("Failed to create CGImage from CIImage")
            return nil
        }

        // Create a UIImage from the base CGImage
        let baseImage = UIImage(cgImage: baseCGImage)
        
        // Create a graphics context for the new image
        UIGraphicsBeginImageContext(baseImage.size)

        // Draw the base image
        baseImage.draw(in: CGRect(origin: .zero, size: baseImage.size))
        let flippedY = baseImage.size.height - y

        let centerPoint = CGPoint(x: x, y: flippedY)

        let fifteenpercent = 0.15
        let outerRadius: CGFloat = max(markSize.width, markSize.height) / 2
        let gap: CGFloat = outerRadius * fifteenpercent
        
        // Get the click mark path
        drawConcentricCircles(center: centerPoint, outerRadius: outerRadius, gap: gap)
        
        // Get the resulting image from the graphics context
        let resultingImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
       
        guard let resultingImage = resultingImage,
           let ciImage = CIImage(image: resultingImage) else {
            return nil
        }

        return ciImage
    }
    
    func drawConcentricCircles(center: CGPoint, outerRadius: CGFloat, gap: CGFloat) {
        // Define radii for the circles
        let secondOuterRadius = outerRadius - gap
        let middleRadius = secondOuterRadius - gap
        let innerRadius = middleRadius - gap

        // Draw the outermost circle
        let outerCirclePath = UIBezierPath(arcCenter: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.systemTeal.setFill() // Outermost circle color
        outerCirclePath.fill()

        // Draw the second outer circle (creates the first gap)
        let secondOuterCirclePath = UIBezierPath(arcCenter: center, radius: secondOuterRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.white.setFill() // Gap color
        secondOuterCirclePath.fill()

        // Draw the middle circle
        let middleCirclePath = UIBezierPath(arcCenter: center, radius: middleRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.systemTeal.setFill() // Middle circle color
        middleCirclePath.fill()

        // Draw the inner circle (creates the second gap)
        let innerCirclePath = UIBezierPath(arcCenter: center, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.white.setFill() // Gap color
        innerCirclePath.fill()

        // Draw the innermost circle
        let innermostCirclePath = UIBezierPath(arcCenter: center, radius: innerRadius - gap, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.systemTeal.setFill() // Innermost circle color
        innermostCirclePath.fill()
    }
}
