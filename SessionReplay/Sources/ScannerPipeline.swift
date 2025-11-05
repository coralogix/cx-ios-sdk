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
        completion: @escaping (CIImage?,URLEntry?) -> Void
    ) {
        guard let urlEntry = urlEntry else {
            Log.e("Missing urlEntry")
            completion(nil, urlEntry)
            return
        }
        
        // Decode CIImage once and reuse it
        guard let originalImage = urlEntry.ciImage else {
            Log.e("Failed to decode screenshot data into CIImage.")
            completion(nil, urlEntry)
            return
        }
        
        var isTextScannerEnabled = false
        var isFaceScannerEnabled = false
        var isImageScannerEnabled = false
        
        isTextScannerEnabled = !(options.maskText?.isEmpty ?? true)
        isFaceScannerEnabled = options.maskFaces
        isImageScannerEnabled = options.maskAllImages

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
                maskAll: !options.maskCreditCard,
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
