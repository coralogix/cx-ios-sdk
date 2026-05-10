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
        configureRecognitionRequest(request)

        performTextRecognition(request, on: image)

        let flippedMaskLayer = flipVertically(maskLayer, height: image.extent.height)
        return flippedMaskLayer.composited(over: image)
    }

    /// Tunes the Vision text recognition request to be permissive enough for
    /// "mask everything that looks like text". The default `VNRecognizeTextRequest`
    /// is gated to `en-US` only and runs language correction, both of which cause
    /// real text to be invisible to the masker (non-English UI strings, short
    /// tokens like "OK"/"$4.99", IDs, version numbers, code-like labels).
    internal func configureRecognitionRequest(_ request: VNRecognizeTextRequest) {
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        } else {
            // Vision's OCR language coverage grew incrementally:
            //   iOS 13     → en-US only
            //   iOS 14.0+  → fr/it/de/es/pt-BR/zh-Hans/zh-Hant
            //   iOS 14.5+  → ru/uk
            //   iOS 15.4+  → ja/ko
            // Setting unsupported languages can cause `perform()` to throw on
            // older OSes, so intersect with what the runtime actually supports.
            let desired = [
                "en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR",
                "zh-Hans", "zh-Hant", "ja-JP", "ko-KR", "ru-RU", "uk-UA"
            ]
            let supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
                for: .accurate,
                revision: VNRecognizeTextRequest.currentRevision)) ?? ["en-US"]
            let supportedSet = Set(supported)
            request.recognitionLanguages = desired.filter { supportedSet.contains($0) }
        }
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
        guard let range = candidate.string.range(of: pattern, options: .regularExpression) else {
            return nil
        }
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
