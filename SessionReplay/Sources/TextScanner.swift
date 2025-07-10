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
    ///   - maskText:  Optional regex patterns to decide which text to mask.
    public func processImage(ciImage: CIImage,
                             maskText: [String]? = nil,
                             completion: @escaping (CIImage) -> Void) {
        
        let maskedImage = self.maskText(in: ciImage, with: maskText)
        
        completion(maskedImage)
    }
    
    /// Masks text regions in the provided image.
    /// - Parameter image: The input `CIImage` to process.
    /// - Returns: A new `CIImage` with text regions masked.
    /// - Mask the Detected Text Regions: For each matching text, determine its bounding box,
    ///   adjust it to the image's coordinate system, and overlay a mask on that region.    
    internal func maskText(in image: CIImage, with patterns: [String]?) -> CIImage {
        let blackColor = CIColor.black
        var maskLayer = CIImage.empty().cropped(to: image.extent)

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                Log.e("No text detected or an error occurred: \(String(describing: error))")
                return
            }

            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                maskLayer = self?.processCandidate(topCandidate, in: image, with: patterns, baseMask: maskLayer, color: blackColor) ?? maskLayer
            }
        }

        performTextRecognition(request, on: image)

        let flippedMaskLayer = flipVertically(maskLayer, height: image.extent.height)
        return flippedMaskLayer.composited(over: image)
    }
    
    private func performTextRecognition(_ request: VNRequest, on image: CIImage) {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.e("Failed to perform text detection: \(error)")
        }
    }
    
    private func processCandidate(_ candidate: VNRecognizedText,
                                  in image: CIImage,
                                  with patterns: [String]?,
                                  baseMask: CIImage,
                                  color: CIColor) -> CIImage {
        var updatedMask = baseMask
        let recognizedText = candidate.string

        guard let patterns = patterns else { return baseMask }

        for pattern in patterns {
            if matchesPattern(recognizedText, pattern: pattern) {
                if let masked = maskCandidate(candidate, in: image, matching: pattern, color: color) {
                    updatedMask = masked.composited(over: updatedMask)
                }
                break
            }
        }
        return updatedMask
    }
    
    private func matchesPattern(_ text: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        } catch {
            Log.e("Invalid regex pattern: \(pattern)")
            return false
        }
    }
    
    private func maskCandidate(_ candidate: VNRecognizedText,
                               in image: CIImage,
                               matching pattern: String,
                               color: CIColor) -> CIImage? {
        guard let range = candidate.string.range(of: pattern) else { return nil }

        do {
            let wordBox = try candidate.boundingBox(for: range)
            guard let boundingBox = wordBox?.boundingBox else { return nil }

            let adjustedRect = CGRect(
                x: boundingBox.minX * image.extent.width,
                y: (1 - boundingBox.minY - boundingBox.height) * image.extent.height,
                width: boundingBox.width * image.extent.width,
                height: boundingBox.height * image.extent.height
            )

            return CIImage(color: color).cropped(to: adjustedRect)
        } catch {
            Log.e("Error getting bounding box: \(error)")
            return nil
        }
    }
    
    private func flipVertically(_ image: CIImage, height: CGFloat) -> CIImage {
        return image
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: height))
    }
}
