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
        let hasMatchAll = patterns?.contains(where: { Self.isMatchAllPattern($0) }) ?? false

        let recognizeRequest = VNRecognizeTextRequest { [weak self] request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                maskLayer = self?.processCandidate(topCandidate,
                                                   observationBox: observation.boundingBox,
                                                   in: image,
                                                   with: patterns,
                                                   baseMask: maskLayer,
                                                   color: blackColor) ?? maskLayer
            }
        }
        configureRecognitionRequest(recognizeRequest)

        var requests: [VNRequest] = [recognizeRequest]

        // For maskAllTexts (pattern includes `.*`/`.+`) also run a region-only
        // pass. `VNRecognizeTextRequest` periodically misses lines its recognizer
        // can't confidently transcribe — observed on wrapped paragraph rows and
        // dense punctuation tokens. `VNDetectTextRectanglesRequest` is purely
        // geometric ("does this look like text?"), much cheaper than recognition,
        // and catches regions the recognizer drops, including scripts Vision has
        // no OCR support for (e.g. Hebrew, Greek).
        if hasMatchAll {
            let regionsRequest = VNDetectTextRectanglesRequest { [weak self] request, _ in
                guard let observations = request.results as? [VNTextObservation] else { return }
                for observation in observations {
                    if let masked = self?.maskNormalizedRect(observation.boundingBox,
                                                             in: image,
                                                             color: blackColor) {
                        maskLayer = masked.composited(over: maskLayer)
                    }
                }
            }
            regionsRequest.reportCharacterBoxes = false
            requests.append(regionsRequest)
        }

        performRequests(requests, on: image)

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

        // Always supply an explicit multi-script language list. Vision's OCR
        // language coverage grew incrementally:
        //   iOS 13     → en-US only
        //   iOS 14.0+  → fr/it/de/es/pt-BR/zh-Hans/zh-Hant
        //   iOS 14.5+  → ru/uk
        //   iOS 15.4+  → ja/ko
        //   iOS 16.0+  → ar
        //   iOS 17.0+  → th/vi
        // Setting unsupported languages can cause `perform()` to throw on older
        // OSes, so intersect with what the runtime actually supports.
        //
        // On iOS 16+ we additionally enable automaticallyDetectsLanguage: per
        // Apple's docs this biases detection per-image using recognitionLanguages
        // as candidates. Relying on automaticallyDetectsLanguage alone caused
        // mixed-script frames (e.g. Latin + Cyrillic + CJK on screen at once) to
        // collapse to a single dominant script and silently drop the others, so
        // we always set the explicit list as well.
        //
        // Hebrew/Greek are included as candidates but Vision currently has no
        // OCR support for those scripts, so supportedRecognitionLanguages will
        // filter them out — their text will remain unmasked unless the host app
        // explicitly wraps it with a mask region.
        let desired = [
            "en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR",
            "zh-Hans", "zh-Hant", "ja-JP", "ko-KR", "ru-RU", "uk-UA",
            "ar-SA", "th-TH", "vi-VN", "he-IL", "el-GR"
        ]
        let supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: VNRecognizeTextRequest.currentRevision)) ?? ["en-US"]
        let supportedSet = Set(supported)
        request.recognitionLanguages = desired.filter { supportedSet.contains($0) }

        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        }
    }
    
    private func performRequests(_ requests: [VNRequest], on image: CIImage) {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            Log.e("Failed to perform text detection: \(error)")
        }
    }

    /// Translates a Vision-normalized rect (origin bottom-left, [0,1] units)
    /// into a CIImage-extent rect with origin flipped to top-left, then returns
    /// a solid-color CIImage cropped to that rect.
    private func maskNormalizedRect(_ normalizedRect: CGRect,
                                    in image: CIImage,
                                    color: CIColor) -> CIImage {
        let adjustedRect = CGRect(
            x: normalizedRect.minX * image.extent.width,
            y: (1 - normalizedRect.minY - normalizedRect.height) * image.extent.height,
            width: normalizedRect.width * image.extent.width,
            height: normalizedRect.height * image.extent.height
        )
        return CIImage(color: color).cropped(to: adjustedRect)
    }
    
    private func processCandidate(_ candidate: VNRecognizedText,
                                  observationBox: CGRect,
                                  in image: CIImage,
                                  with patterns: [String]?,
                                  baseMask: CIImage,
                                  color: CIColor) -> CIImage {
        var updatedMask = baseMask
        let recognizedText = candidate.string

        guard let patterns = patterns else { return baseMask }

        for pattern in patterns {
            if matchesPattern(recognizedText, pattern: pattern) {
                if let masked = maskCandidate(candidate,
                                              observationBox: observationBox,
                                              in: image,
                                              matching: pattern,
                                              color: color) {
                    updatedMask = masked.composited(over: updatedMask)
                }
                break
            }
        }
        return updatedMask
    }

    /// Match-all regex patterns sent by the Flutter/RN bridges when the host
    /// enables `maskAllTexts`. For these we want the entire observation rect,
    /// not a per-character substring box — Vision's per-range mapping is
    /// brittle for dense punctuation tokens (e.g. `"OK · USB-C · v2.6.3"`) and
    /// returns nil, causing the whole line to escape the mask.
    private static func isMatchAllPattern(_ pattern: String) -> Bool {
        pattern == ".*" || pattern == ".+"
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
                               observationBox: CGRect,
                               in image: CIImage,
                               matching pattern: String,
                               color: CIColor) -> CIImage? {
        let normalizedRect: CGRect

        if Self.isMatchAllPattern(pattern) {
            normalizedRect = observationBox
        } else {
            guard let range = candidate.string.range(of: pattern, options: .regularExpression) else {
                return nil
            }
            do {
                let wordBox = try candidate.boundingBox(for: range)
                guard let boundingBox = wordBox?.boundingBox else { return nil }
                normalizedRect = boundingBox
            } catch {
                Log.e("Error getting bounding box: \(error)")
                return nil
            }
        }

        return maskNormalizedRect(normalizedRect, in: image, color: color)
    }
    
    private func flipVertically(_ image: CIImage, height: CGFloat) -> CIImage {
        return image
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: height))
    }
}
