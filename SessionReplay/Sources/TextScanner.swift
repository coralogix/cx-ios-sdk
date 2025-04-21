//
//  TextScanner.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 28/11/2024.
//

import Foundation
import Vision
import CoreImage
import UIKit
import CoralogixInternal

public class TextScanner {
    
    private let context = CIContext()
    
    public init() {
        // Initialization code if needed
    }
    
    /// Processes the image at the given URL by masking detected text and saves the result to a new file.
    /// - Parameters:
    ///   - inputURL: The file URL of the input image.
    ///   - outputURL: The file URL where the processed image will be saved.
    public func processImage(at inputURL: URL,
                             maskText: [String]? = nil,
                             completion: @escaping (Bool, Int, Int) -> Void) {
        guard let inputImage = CIImage(contentsOf: inputURL) else {
            completion(false, 0, 0)
            return
        }
        
        let (maskedImage, totalTextCount, maskedTextCount) = self.maskText(in: inputImage, with: maskText)
        
        SRUtils.saveImage(maskedImage, outputURL: inputURL) { isSuccess in
            completion(isSuccess, totalTextCount, maskedTextCount)
        }
    }
    
    /// Masks text regions in the provided image.
    /// - Parameter image: The input `CIImage` to process.
    /// - Returns: A new `CIImage` with text regions masked.
    /// - Mask the Detected Text Regions: For each matching text, determine its bounding box,
    ///   adjust it to the image's coordinate system, and overlay a mask on that region.
    internal func maskText(in image: CIImage, with patterns: [String]?) -> (CIImage, Int, Int) {
        let blackColor = CIColor.black
        var maskLayer = CIImage.empty().cropped(to: image.extent)
        var totalTextCount = 0
        var maskedTextCount = 0

        let request = VNRecognizeTextRequest { (request, error) in
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                Log.e("No text detected or an error occurred: \(String(describing: error))")
                return
            }
            
            totalTextCount = results.count
            
            for observation in results {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                let recognizedText = topCandidate.string
                
                // Determine if we should mask this text
                let shouldMask: Bool
                if let patterns = patterns {
                    // Mask if any pattern matches
                    shouldMask = patterns.contains { pattern in
                        recognizedText.range(of: pattern, options: .regularExpression) != nil
                    }
                } else {
                    // Mask all text if patterns is nil
                    shouldMask = true
                }
                
                if shouldMask {
                    maskedTextCount += 1
                    let boundingBox = observation.boundingBox
                    let adjustedRect = CGRect(
                        x: boundingBox.minX * image.extent.width,
                        y: (1 - boundingBox.minY - boundingBox.height) * image.extent.height,
                        width: boundingBox.width * image.extent.width,
                        height: boundingBox.height * image.extent.height
                    )
                    
                    let mask = CIImage(color: blackColor).cropped(to: adjustedRect)
                    maskLayer = mask.composited(over: maskLayer)
                }
            }
        }
        
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            Log.e("Failed to perform text detection: \(error)")
            return (image, 0, 0)
        }
        
        let flippedMaskLayer = maskLayer
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: image.extent.height))
        
        return (flippedMaskLayer.composited(over: image), totalTextCount, maskedTextCount)
    }
}
