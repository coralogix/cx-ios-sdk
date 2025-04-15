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
    func processImage(at inputURL: URL,
                      completion: @escaping (Bool) -> Void) {
        guard let ciImage = CIImage(contentsOf: inputURL) else {
            Log.e("Failed to load image.")
            completion(false)
            return
        }
        
        guard let clickedCGImage = self.addClickMark(to: ciImage, at: 100, y: 100) else {
            completion(false)
            return
        }
    
        Utils.saveImage(clickedCGImage, outputURL: inputURL) { isSuccess in
            completion(isSuccess)
        }
    }
    
    // Function to add a programmatically created click mark to a CIImage
    func addClickMark(to ciImage: CIImage, at x: CGFloat, y: CGFloat, markSize: CGSize = CGSize(width: 50, height: 50)) -> CGImage? {
        // Create a CIContext
        let context = CIContext()

        // Convert the CIImage to a CGImage
        guard let baseCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage from CIImage")
            return nil
        }

        // Create a UIImage from the base CGImage
        let baseImage = UIImage(cgImage: baseCGImage)

        // Create a graphics context for the new image
        UIGraphicsBeginImageContext(baseImage.size)

        // Draw the base image
        baseImage.draw(in: CGRect(origin: .zero, size: baseImage.size))

        // Define the click mark center
        let adjustedY = baseImage.size.height - y // Adjust for flipped Y-axis
        let centerPoint = CGPoint(x: x, y: adjustedY)

   
        let outerRadius: CGFloat = 60 // Outer circle radius
        let gap: CGFloat = 10
        
        // Get the click mark path
        drawConcentricCircles(center: centerPoint, outerRadius: outerRadius, gap: gap)
        
        // Get the resulting image from the graphics context
        let resultingImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Convert the resulting UIImage back to CGImage
        guard let resultingCGImage = resultingImage?.cgImage else {
            print("Failed to convert resulting UIImage to CGImage")
            return nil
        }

        return resultingCGImage
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
        
    func addClickMark(to ciImage: CIImage, at x: CGFloat, y: CGFloat, clickMark: UIImage) -> CGImage? {
        // Create a CIContext
        let context = CIContext()

        // Convert the CIImage to a CGImage
        guard let baseCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage from CIImage")
            return nil
        }

        // Create a UIImage from the base CGImage
        let baseImage = UIImage(cgImage: baseCGImage)

        // Create a graphics context for the new image
        UIGraphicsBeginImageContext(baseImage.size)

        // Draw the base image
        baseImage.draw(in: CGRect(origin: .zero, size: baseImage.size))

        // Draw the click mark image at the specified coordinates
        let clickMarkSize = CGSize(width: 50, height: 50) // Adjust size as needed
        let clickMarkRect = CGRect(
            x: x - clickMarkSize.width / 2, // Center the click mark
            y: baseImage.size.height - y - clickMarkSize.height / 2, // Adjust for flipped Y-axis
            width: clickMarkSize.width,
            height: clickMarkSize.height
        )
        clickMark.draw(in: clickMarkRect)

        // Get the resulting image from the graphics context
        let resultingImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Convert the resulting UIImage back to CIImage
        guard let resultingCGImage = resultingImage?.cgImage else {
            print("Failed to convert resulting UIImage to CIImage")
            return nil
        }

        return resultingCGImage
    }
}
