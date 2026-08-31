//
//  ScannerPipeline.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 12/12/2024.
//

import Foundation
import CoreImage
import CoralogixInternal

extension Array where Element == CGRect {
    /// Whether a tap at `point` (screen points) landed inside one of a frame's masked regions.
    ///
    /// Fails closed: any rect containing the point counts, including one belonging to a window a
    /// higher z-order layer later painted over. Resolving stacking precisely would risk drawing a
    /// marker over content the customer asked to be masked; the cost of the conservative answer is
    /// only a missing marker in a rare layering case.
    ///
    /// Internal, and deliberately not on the shared `CoralogixInternal` surface: the capture pass
    /// only collects the rects, and this question is asked in exactly one place — here.
    ///
    /// `CGRect.contains` excludes the `maxX`/`maxY` edges, so a tap exactly on a mask's bottom or
    /// right boundary reads as outside and still draws a marker. Left as-is: the marker is centred
    /// on the tap, and its radius already overlaps masked pixels for any tap within ~25pt of a
    /// mask, so treating the boundary as inside would not stop that — only insetting every rect by
    /// the marker radius would, which would suppress markers well outside the masked area.
    func containsTap(_ point: CGPoint) -> Bool {
        contains { $0.contains(point) }
    }
}

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
        //
        // The UIKit walk reports geometry back (URLEntry.maskRects), and the Dart bitmap
        // provider reports the rects it masked alongside each frame (FlutterViewBitmap.maskRects,
        // merged in captureFrame) — with no bitmap to paste, the blacked-out Flutter region is
        // reported whole. The OCR/Vision stages mask pixels in place and report none,
        // so a tap over content masked only by those still draws its marker. Suppressing those
        // needs the scanners to surface their observation rects in screen points, which is its
        // own work.
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

            // A tap inside a masked region is drawn nowhere: the marker would give away which
            // element under the mask was hit, and a run of markers reconstructs what was entered
            // on a masked keypad. The frame itself is kept — only the position is withheld.
            //
            // Tested against the rects the capture pass actually painted, so the marker cannot
            // contradict the pixels. Regions masked by the OCR/Vision stages above report no
            // geometry and so cannot suppress a marker — see the SwiftUI note in runPipeline.
            guard !urlEntry.maskRects.containsTap(point) else {
                Log.d("[SR] tap inside a masked region — marker suppressed")
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
