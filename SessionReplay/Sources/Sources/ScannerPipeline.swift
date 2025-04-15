//
//  ScannerPipeline.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 12/12/2024.
//
import Foundation
import CoralogixInternal

class ScannerPipeline {
    var isImageScannerEnabled: Bool = false
    var isTextScannerEnabled: Bool = false
    var isFaceScannerEnabled: Bool = false
    
    private let textScanner = TextScanner()
    private let imageScanner = ImageScanner()
    private let faceScanner = FaceScanner()
    private let clickScanner = ClickScanner()
    
    func runPipeline(inputURL: URL,
                     options: SessionReplayOptions,
                     completion: @escaping (Bool) -> Void) {
        
        // Run Image Scanner if enabled
        if isImageScannerEnabled {
            imageScanner.processImage(at: inputURL,
                                      maskAll: options.maskAllImages,
                                      creditCardPredicate: options.creditCardPredicate) { result, _, _ in
                self.runTextScanner(inputURL: inputURL, options: options, completion: completion)
            }
        } else {
            runTextScanner(inputURL: inputURL, options: options, completion: completion)
        }
    }
    
    private func runTextScanner(inputURL: URL,
                                options: SessionReplayOptions,
                                completion: @escaping (Bool) -> Void) {
        // Run Text Scanner if enabled
        if isTextScannerEnabled {
            textScanner.processImage(at: inputURL, maskText: options.maskText) { result, _, _ in
                self.runFaceScanner(inputURL: inputURL, options: options, completion: completion)
            }
        } else {
            runFaceScanner(inputURL: inputURL, options: options, completion: completion)
        }
    }
    
    private func runFaceScanner(inputURL: URL,
                                options: SessionReplayOptions,
                                completion: @escaping (Bool) -> Void) {
#if targetEnvironment(simulator)
        // Skip face scanning on the simulator
        Log.e("Skipping FaceScanner as we are running on the simulator")
        runClickScanner(inputURL: inputURL, options: options, completion: completion)
#else
        // Run Face Scanner if enabled
        if isFaceScannerEnabled {
            faceScanner.processImage(at: inputURL) { result in
                Log.d("FaceScanner completed successfully.")
                runClickScanner(inputURL: inputURL, options: options, completion: completion)
            }
        } else {
            Log.d("Pipeline completed without FaceScanner.")
            runClickScanner(inputURL: inputURL, options: options, completion: completion)
        }
#endif
    }
    
    private func runClickScanner(inputURL: URL,
                                 options: SessionReplayOptions,
                                 completion: @escaping (Bool) -> Void) {
        clickScanner.processImage(at: inputURL) { result in
            completion(result)
        }
    }
}
