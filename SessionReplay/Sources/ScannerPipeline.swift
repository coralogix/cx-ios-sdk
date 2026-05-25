//
//  ScannerPipeline.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 12/12/2024.
//

import Foundation
import CoreImage
import CoralogixInternal

class ScannerPipeline {
    func runPipeline(
        options: SessionReplayOptions,
        urlEntry: URLEntry? = nil,
        completion: @escaping (CIImage?, URLEntry?) -> Void
    ) {
        guard let urlEntry = urlEntry else {
            Log.e("Missing urlEntry")
            completion(nil, urlEntry)
            return
        }

        guard let originalImage = urlEntry.ciImage else {
            Log.e("Failed to decode screenshot data into CIImage.")
            completion(nil, urlEntry)
            return
        }

        // ImageScanner: credit-card image detection only (uses Vision rectangle + OCR).
        // General image masking is handled synchronously by the UIImageView walk in UIViewExt.
        // TextScanner removed: native text masking is done by the synchronous UILabel walk;
        // Flutter text masking is handled by the Dart bitmap provider (pre-masked bitmap).
        let isImageScannerEnabled = options.maskOnlyCreditCards
        let isFaceScannerEnabled = options.maskFaces

        let imageScanner = ImageScanner()
        let faceScanner = FaceScanner()
        let clickScanner = ClickScanner()

        func runImageScanner(input: CIImage, completion: @escaping (CIImage) -> Void) {
            guard isImageScannerEnabled else {
                completion(input)
                return
            }

            imageScanner.processImage(
                screenshotData: urlEntry.screenshotData,
                maskAll: false,
                creditCardPredicate: options.creditCardPredicate
            ) { outputImage in
                completion(outputImage ?? input)
            }
        }

        func runFaceScanner(input: CIImage, completion: @escaping (CIImage) -> Void) {
#if targetEnvironment(simulator)
            Log.e("Skipping FaceScanner as we are running on the simulator")
            completion(input)
#else
            guard isFaceScannerEnabled else {
                completion(input)
                return
            }

            faceScanner.processImage(at: input) { outputImage in
                completion(outputImage ?? input)
            }
#endif
        }

        func runClickScanner(input: CIImage, completion: @escaping (CIImage) -> Void) {
            guard let point = urlEntry.point else {
                Log.e("Tap point not provided. Cannot run ClickScanner.")
                completion(input)
                return
            }

            clickScanner.processImage(at: input, x: point.x, y: point.y) { outputImage in
                completion(outputImage ?? input)
            }
        }

        runImageScanner(input: originalImage) { img1 in
            runFaceScanner(input: img1) { img2 in
                runClickScanner(input: img2) { finalImage in
                    completion(finalImage, urlEntry)
                }
            }
        }
    }
}
