//
//  ScannerPipeline.swift
//  session-replay
//
//  Created by Tomer Har Yoffi on 12/12/2024.
//

class ScannerPipeline {
    var isImageScannerEnabled: Bool = false
    var isTextScannerEnabled: Bool = false
    var isFaceScannerEnabled: Bool = false
    
    private let textScanner = TextScanner()
    private let imageScanner = ImageScanner()
    private let faceScanner = FaceScanner()
    
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
    completion(true)
    #else
        // Run Face Scanner if enabled
        if isFaceScannerEnabled {
            faceScanner.processImage(at: inputURL) { result in
                if result {
                    Log.d("FaceScanner completed successfully.")
                    completion(true)
                } else {
                    Log.d("FaceScanner failed")
                    completion(false)
                }
            }
        } else {
            Log.d("Pipeline completed without FaceScanner.")
            completion(true)
        }
    #endif
    }
}
