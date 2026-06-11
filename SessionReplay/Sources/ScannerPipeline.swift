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

        // Masking responsibilities by content type:
        // - UIKit text/images: synchronous UILabel/UIImageView walk in UIViewExt (deterministic).
        // - Flutter: Dart bitmap provider delivers a pre-masked bitmap.
        // - SwiftUI: the UIView walk cannot see inside hosting views, so captures whose
        //   scene contains SwiftUI content (urlEntry.containsSwiftUIContent) additionally
        //   run the Vision-based TextScanner (OCR) and ImageScanner maskAll (rectangle
        //   detection) stages here. Probabilistic — accepted interim trade-off (BUGV2-6045).
        // - Credit-card image detection (ImageScanner, maskAll: false) runs for everyone
        //   when enabled.
        let needsSwiftUIMasking = urlEntry.containsSwiftUIContent
        let isTextScannerEnabled = needsSwiftUIMasking && !(options.maskText?.isEmpty ?? true)
        let isImageScannerEnabled = options.maskOnlyCreditCards || (needsSwiftUIMasking && options.maskAllImages)
        let isFaceScannerEnabled = options.maskFaces

        let imageScanner = ImageScanner()
        let textScanner = TextScanner()
        let faceScanner = FaceScanner()
        let clickScanner = ClickScanner()

        func runImageScanner(input: CIImage, completion: @escaping (CIImage) -> Void) {
            guard isImageScannerEnabled else {
                completion(input)
                return
            }

            imageScanner.processImage(
                screenshotData: urlEntry.screenshotData,
                maskAll: needsSwiftUIMasking && options.maskAllImages && !options.maskOnlyCreditCards,
                creditCardPredicate: options.creditCardPredicate
            ) { outputImage in
                completion(outputImage ?? input)
            }
        }

        func runTextScanner(input: CIImage, completion: @escaping (CIImage) -> Void) {
            guard isTextScannerEnabled else {
                completion(input)
                return
            }

            textScanner.processImage(ciImage: input, maskText: options.maskText) { outputImage in
                completion(outputImage)
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
            runTextScanner(input: img1) { img2 in
                runFaceScanner(input: img2) { img3 in
                    runClickScanner(input: img3) { finalImage in
                        completion(finalImage, urlEntry)
                    }
                }
            }
        }
    }
}
