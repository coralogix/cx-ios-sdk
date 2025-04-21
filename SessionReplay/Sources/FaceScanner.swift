//
//  FaceScanner.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 09/12/2024.
//

import Vision
import UIKit
import CoralogixInternal

class FaceScanner {
    
    /// Detects faces in the image and masks them with a black rectangle.
    /// - Parameters:
    ///   - image: The input `UIImage` to process.
    ///   - completion: A closure returning the processed image with faces masked or an error.
    func processImage(at inputURL: URL, completion: @escaping (Bool) -> Void) {
        guard let ciImage = CIImage(contentsOf: inputURL),
              let cgImage = Utils.convertCIImageToCGImage(ciImage) else {
            Log.e("Failed to load image.")
            completion(false)
            return
        }
        
        // Create the face detection request
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                Log.e("Face detection error: \(error)")
                completion(false)
                return
            }
            
            guard let observations = request.results as? [VNFaceObservation], !observations.isEmpty else {
                Log.e("No faces detected.")
                completion(false) // Return the original image if no faces are detected
                return
            }
            
            // Process the image and mask detected faces
            let maskedImage = self.applyFaceMask(to: UIImage(cgImage: cgImage), with: observations)
            if let cgImage = maskedImage?.cgImage {
                Utils.saveImage(cgImage, outputURL: inputURL) { isSuccess in
                    completion(isSuccess)
                }
                return
            }
            completion(false)
        }
        
        // Perform the request
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try requestHandler.perform([faceDetectionRequest])
        } catch {
            Log.e("Failed to perform face detection: \(error)")
            completion(false)
        }
    }
    
    /// Applies a black mask over the detected face rectangles in the image.
    /// - Parameters:
    ///   - image: The original `UIImage` to process.
    ///   - observations: An array of `VNFaceObservation` with detected face rectangles.
    /// - Returns: A new `UIImage` with the faces masked.
    internal func applyFaceMask(to image: UIImage, with observations: [VNFaceObservation]) -> UIImage? {
        let imageSize = CGSize(width: image.size.width, height: image.size.height)
        
        // Begin drawing on the image
        UIGraphicsBeginImageContextWithOptions(CGSize(width: imageSize.width, height: imageSize.height), false, 1.0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            print("Failed to create graphics context.")
            return nil
        }
        
        // Draw the original image
        image.draw(in: CGRect(origin: .zero, size: imageSize))
        
        // Set the mask color to black
        context.setFillColor(UIColor.black.cgColor)
        
        // Draw rectangles over detected faces
        for faceObservation in observations {
            let boundingBox = faceObservation.boundingBox
            let rect = CGRect(
                x: boundingBox.origin.x * imageSize.width,
                y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
                width: boundingBox.width * imageSize.width,
                height: boundingBox.height * imageSize.height
            )
            context.fill(rect)
        }
        
        // Get the final image
        let maskedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return maskedImage
    }
}
