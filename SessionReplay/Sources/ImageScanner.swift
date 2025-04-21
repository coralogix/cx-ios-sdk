//
//  CreditcardScanner.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 08/12/2024.
//

import UIKit
import Vision
import CoreImage
import CoralogixInternal

public class ImageScanner {
    let matches = 2
    var creditCardPredicate: [String]? = nil
    
    // Function to process the image, detect Images, and mask them
    func processImage(at inputURL: URL,
                      maskAll: Bool = false,
                      creditCardPredicate: [String]? = nil,
                      completion: @escaping (Bool, Int, Int) -> Void) {
        guard let ciImage = CIImage(contentsOf: inputURL),
              let cgImage = Utils.convertCIImageToCGImage(ciImage) else {
            Log.e("Failed to load image.")
            completion(false, 0, 0)
            return
        }

        self.creditCardPredicate = creditCardPredicate

        func processRectangles(
            _ rectangles: [VNRectangleObservation],
            in ciImage: CIImage,
            using cgImage: CGImage
        ) {
            Task {
                var maskedImage = ciImage
                let totalImagesCount = rectangles.count
                var maskedImagesCount = 0
                
                for observation in rectangles {
                    if maskAll {
                        if let newMaskedImage = await maskRectangle(in: maskedImage, using: observation) {
                            maskedImage = newMaskedImage
                            maskedImagesCount += 1
                        }
                    } else {
                        let isCreditCard = await isCreditCardRectangle(cgImage: cgImage, observation: observation)
                        if isCreditCard {
                            if let newMaskedImage = await maskRectangle(in: maskedImage, using: observation) {
                                maskedImage = newMaskedImage
                                maskedImagesCount += 1
                            }
                        }
                    }
                }
                
                saveMaskedImage(maskedImage,
                                to: inputURL,
                                totalImagesCount: totalImagesCount,
                                maskedImagesCount: maskedImagesCount)
            }
        }
        
        
        func saveMaskedImage(_ maskedImage: CIImage, to url: URL,  totalImagesCount: Int, maskedImagesCount: Int) {
            Utils.saveImage(maskedImage, outputURL: url) { result in
                completion(result, totalImagesCount, maskedImagesCount)
            }
        }
        
        func configureRectangleDetectionRequest() -> VNDetectRectanglesRequest {
            let request = VNDetectRectanglesRequest { request, _ in
                guard let results = request.results as? [VNRectangleObservation], !results.isEmpty else {
                    Log.e("No rectangles detected.")
                    completion(false, 0, 0)
                    return
                }
                
                processRectangles(results, in: ciImage, using: cgImage)
            }
            request.minimumSize = 0.05
            request.maximumObservations = 10
            request.minimumAspectRatio = 0.2
            request.maximumAspectRatio = 1.0
            request.quadratureTolerance = 20.0
            return request
        }
        
        let rectangleDetectionRequest = configureRectangleDetectionRequest()
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        do {
            try imageRequestHandler.perform([rectangleDetectionRequest])
        } catch {
            Log.e("Failed to perform rectangle detection: \(error)")
            completion(false, 0, 0)
        }
    }
    
    func maskRectangle(in image: CIImage, using observation: VNRectangleObservation) async -> CIImage? {
        await withCheckedContinuation { continuation in
            self.maskRectangle(in: image, using: observation) { newImage in
                continuation.resume(returning: newImage)
            }
        }
    }

    func isCreditCardRectangle(cgImage: CGImage, observation: VNRectangleObservation) async -> Bool {
        await withCheckedContinuation { continuation in
            self.isCreditCardRectangle(cgImage: cgImage, observation: observation) { result in
                continuation.resume(returning: result)
            }
        }
    }

    func isCreditCardRectangle(cgImage: CGImage,
                               observation: VNRectangleObservation,
                               completion: @escaping (Bool) -> Void) {
        // Step 2: Extract and correct the perspective of the detected rectangle
        if let correctedImage = self.extractAndCorrectRectangle(from: cgImage,
                                                                using: observation) {
            
            // Step 3: Recognize text within the corrected image
            self.recognizeText(in: correctedImage) { isCreditCard in
                completion(isCreditCard)
            }
        } else {
            completion(false)
        }
    }

    func maskRectangle(in ciImage: CIImage, using observation: VNRectangleObservation, completion: @escaping (CIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            
            // Get the image size
            let imageSize = ciImage.extent.size
            
            // Convert normalized rectangle coordinates to image coordinates
            let topLeft = CGPoint(x: observation.topLeft.x * imageSize.width,
                                  y: (1 - observation.topLeft.y) * imageSize.height)
            let topRight = CGPoint(x: observation.topRight.x * imageSize.width,
                                   y: (1 - observation.topRight.y) * imageSize.height)
            let bottomLeft = CGPoint(x: observation.bottomLeft.x * imageSize.width,
                                     y: (1 - observation.bottomLeft.y) * imageSize.height)
            let bottomRight = CGPoint(x: observation.bottomRight.x * imageSize.width,
                                      y: (1 - observation.bottomRight.y) * imageSize.height)
            
            // Create a CGPath for the rectangle
            let path = CGMutablePath()
            path.move(to: topLeft)
            path.addLine(to: topRight)
            path.addLine(to: bottomRight)
            path.addLine(to: bottomLeft)
            path.closeSubpath()
            
            DispatchQueue.main.async {
                // Create a black rectangle mask
                UIGraphicsBeginImageContext(imageSize)
                guard let context = UIGraphicsGetCurrentContext() else {
                    completion(nil)
                    return
                }
                
                // Draw the original image
                let uiImage = UIImage(ciImage: ciImage)
                uiImage.draw(in: CGRect(origin: .zero, size: imageSize))
                
                // Fill the detected rectangle with black
                context.setFillColor(UIColor.black.cgColor)
                context.addPath(path)
                context.fillPath()
                
                // Get the masked image
                let maskedImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                // Convert the masked image back to CIImage
                let result = maskedImage.flatMap { CIImage(image: $0) }
                completion(result)
            }
        }
    }

    // Function to extract and correct the perspective of the detected rectangle
    private func extractAndCorrectRectangle(from image: CGImage, using observation: VNRectangleObservation) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        
        // Coordinates of the rectangle's corners
        let topLeft = observation.topLeft.scaled(to: ciImage.extent.size)
        let topRight = observation.topRight.scaled(to: ciImage.extent.size)
        let bottomLeft = observation.bottomLeft.scaled(to: ciImage.extent.size)
        let bottomRight = observation.bottomRight.scaled(to: ciImage.extent.size)
        
        // Define the destination rectangle (corrected image size)
        let correctedExtent = CGRect(x: 0, y: 0, width: ciImage.extent.width, height: ciImage.extent.height)
        
        // Create a perspective correction filter
        let perspectiveCorrectionFilter = CIFilter(name: "CIPerspectiveCorrection")
        perspectiveCorrectionFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        perspectiveCorrectionFilter?.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        perspectiveCorrectionFilter?.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        perspectiveCorrectionFilter?.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        perspectiveCorrectionFilter?.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        
        // Get the corrected image
        guard let correctedCIImage = perspectiveCorrectionFilter?.outputImage else {
            Log.e("Perspective correction failed.")
            return nil
        }
        
        // Crop the corrected image to the detected rectangle
        let croppedCIImage = correctedCIImage.cropped(to: correctedExtent)
        
        // Convert CIImage to CGImage
        let context = CIContext()
        guard let correctedCGImage = context.createCGImage(croppedCIImage, from: croppedCIImage.extent) else {
            Log.e("Failed to create CGImage from corrected CIImage.")
            return nil
        }
        
        return correctedCGImage
    }
    
    // Function to recognize text in the corrected image
    internal func recognizeText(in image: CGImage, completion: @escaping (Bool) -> Void) {
        let textRecognitionRequest = VNRecognizeTextRequest { request, error in
            var count = 0
            if let error = error {
                Log.e("Text recognition error: \(error)")
                completion(false) // Return false in case of an error
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                Log.e("No text recognized.")
                completion(false) // Return false in case of an error
                return
            }
            
            let allPredicates = (Utils.creditCardWords +
                                 Utils.creditCardPrefixes +
                                 (self.creditCardPredicate ?? [])).map { $0.lowercased() }
            
            for observation in observations {
                //Log.d("Recognized text: \(topCandidate.string)")
                if let topCandidate = observation.topCandidates(1).first {
                    if allPredicates.contains(topCandidate.string.lowercased()) {
                        count += 1
                    }
                }
            }
            // Check if count is greater than 2
            completion(count >= self.matches)
        }
        textRecognitionRequest.recognitionLevel = .accurate
        
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try requestHandler.perform([textRecognitionRequest])
        } catch {
            Log.e("Failed to perform text recognition: \(error)")
            completion(false) // Return false if the request fails
        }
    }
}


// Extension to scale normalized points to image size
private extension CGPoint {
    func scaled(to size: CGSize) -> CGPoint {
        return CGPoint(x: self.x * size.width, y: self.y * size.height)
    }
}
