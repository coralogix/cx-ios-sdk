//
//  ScannerPipeline.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 12/12/2024.
//
import Foundation
import CoralogixInternal
import CoreImage

class ScannerPipeline {
    var isImageScannerEnabled: Bool = false
    var isTextScannerEnabled: Bool = false
    var isFaceScannerEnabled: Bool = false
    
    private let textScanner = TextScanner()
    private let imageScanner = ImageScanner()
    private let faceScanner = FaceScanner()
    private let clickScanner = ClickScanner()
    private let coordinateQueue = DispatchQueue(label: "com.coralogix.scannerPipeline.coordinateQueue")

    private var _tapPoint: CGPoint?
    private var tapPoint: CGPoint? {
        get { coordinateQueue.sync { _tapPoint } }
        set { coordinateQueue.sync { _tapPoint = newValue } }
    }
    
    func runPipelineWithCancellation(
        inputURL: URL,
        screenshotData: Data,
        options: SessionReplayOptions,
        operationId: UUID,
        isValid: @escaping (UUID) -> Bool,
        tapPoint: CGPoint? = nil,
        completion: @escaping (CIImage?) -> Void) {
            self.tapPoint = tapPoint
            
            // If operation is no longer valid, exit early
            guard isValid(operationId) else {
                Log.d("Pipeline operation \(operationId) was cancelled")
                completion(nil)
                return
            }
                
            // Run Image Scanner if enabled
            if isImageScannerEnabled {
                imageScanner.processImage(screenshotData: screenshotData,
                                          maskAll: options.maskAllImages,
                                          creditCardPredicate: options.creditCardPredicate
                ) { [weak self] ciImage in
                    guard let self = self, isValid(operationId) else {
                        // Skip next stage if operation is no longer valid
                        completion(ciImage)
                        return
                    }
                    
                    self.runTextScannerWithCancellation(
                        inputURL: inputURL,
                        screenshotData: screenshotData,
                        ciImage: ciImage,
                        options: options,
                        operationId: operationId,
                        isValid: isValid,
                        completion: completion)
                }
            } else {
                runTextScannerWithCancellation(
                    inputURL: inputURL,
                    screenshotData: screenshotData,
                    ciImage: nil,
                    options: options,
                    operationId: operationId,
                    isValid: isValid,
                    completion: completion
                )
            }
        }
    
    private func runTextScannerWithCancellation(
        inputURL: URL,
        screenshotData: Data,
        ciImage: CIImage?,
        options: SessionReplayOptions,
        operationId: UUID,
        isValid: @escaping (UUID) -> Bool,
        completion: @escaping (CIImage?) -> Void) {
            
            // Check if operation is still valid
            guard isValid(operationId) else {
                completion(ciImage)
                return
            }
            
            let resolvedCIImage = ciImage ?? CIImage(data: screenshotData)
            guard let finalImage = resolvedCIImage else {
                completion(ciImage)
                return
            }
            
            // Run Text Scanner if enabled
            if isTextScannerEnabled {
                textScanner.processImage(ciImage: finalImage, maskText: options.maskText) { [weak self] ciImage in
                    guard let self = self, isValid(operationId) else {
                        // Skip next stage if operation is no longer valid
                        completion(ciImage)
                        return
                    }
                    self.runFaceScannerWithCancellation(
                        inputURL: inputURL,
                        screenshotData: screenshotData,
                        ciImage: ciImage,
                        options: options,
                        operationId: operationId,
                        isValid: isValid,
                        completion: completion
                    )
                }
            } else {
                runFaceScannerWithCancellation(
                    inputURL: inputURL,
                    screenshotData: screenshotData,
                    ciImage: finalImage,
                    options: options,
                    operationId: operationId,
                    isValid: isValid,
                    completion: completion
                )
            }
        }
    
    private func runFaceScannerWithCancellation(
        inputURL: URL,
        screenshotData: Data,
        ciImage: CIImage?,
        options: SessionReplayOptions,
        operationId: UUID,
        isValid: @escaping (UUID) -> Bool,
        completion: @escaping (CIImage?) -> Void) {
            
            // Check if operation is still valid
            guard isValid(operationId) else {
                completion(ciImage)
                return
            }
            
            let resolvedCIImage = ciImage ?? CIImage(data: screenshotData)
            guard let finalImage = resolvedCIImage else {
                completion(ciImage)
                return
            }
#if targetEnvironment(simulator)
            // Skip face scanning on the simulator
            Log.e("Skipping FaceScanner as we are running on the simulator")
            runClickScannerWithCancellation(
                inputURL: inputURL,
                screenshotData: screenshotData,
                ciImage: finalImage,
                options: options,
                operationId: operationId,
                isValid: isValid,
                completion: completion)
#else
            // Run Face Scanner if enabled
            if isFaceScannerEnabled {
                faceScanner.processImage(at: ciImage) { [weak self] ciImage in
                    guard let self = self, isValid(operationId) else {
                        // Skip next stage if operation is no longer valid
                        completion(false)
                        return
                    }
                    
                    let resolvedCIImage = ciImage ?? CIImage(data: screenshotData)
                    guard let finalImage = resolvedCIImage else {
                        completion(false)
                        return
                    }
                    Log.d("FaceScanner completed successfully.")
                    self.runClickScannerWithCancellation(
                        inputURL: inputURL,
                        screenshotData: screenshotData,
                        ciImage: finalImage,
                        options: options,
                        operationId: operationId,
                        isValid: isValid,
                        completion: completion
                    )
                }
            } else {
                Log.d("Pipeline completed without FaceScanner.")
                self.runClickScannerWithCancellation(
                    inputURL: inputURL,
                    screenshotData: screenshotData,
                    ciImage: finalImage,
                    options: options,
                    operationId: operationId,
                    isValid: isValid,
                    completion: completion)
            }
#endif
        }
    
    private func runClickScannerWithCancellation(
        inputURL: URL,
        screenshotData: Data,
        ciImage: CIImage?,
        options: SessionReplayOptions,
        operationId: UUID,
        isValid: @escaping (UUID) -> Bool,
        completion: @escaping (CIImage?) -> Void) {
            
            // Check if operation is still valid
            guard isValid(operationId) else {
                completion(ciImage)
                return
            }
            
            guard let point = self.tapPoint else {
                Log.e("Tap point not provided. Cannot run ClickScanner.")
                completion(ciImage)
                return
            }
            
            let resolvedCIImage = ciImage ?? CIImage(data: screenshotData)
            guard let finalImage = resolvedCIImage else {
                completion(ciImage)
                return
            }
            
            clickScanner.processImage(at: finalImage, x: point.x, y: point.y) { ciImage in
                guard isValid(operationId),
                      let ciImage = ciImage else {
                    // Skip next stage if operation is no longer valid
                    completion(ciImage)
                    return
                }
                
                SRUtils.saveImage(ciImage, outputURL: inputURL) { result in
                    completion(ciImage)
                    return
                }

                completion(ciImage)
            }
        }
}
