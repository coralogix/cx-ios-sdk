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
    
    func runPipelineWithCancellation(
        inputURL: URL,
        options: SessionReplayOptions,
        operationId: UUID,
        isValid: @escaping (UUID) -> Bool,
        completion: @escaping (Bool) -> Void) {
            
            // If operation is no longer valid, exit early
            guard isValid(operationId) else {
                Log.d("Pipeline operation \(operationId) was cancelled")
                completion(false)
                return
            }
            
            // Run Image Scanner if enabled
            if isImageScannerEnabled {
                imageScanner.processImage(at: inputURL,
                                          maskAll: options.maskAllImages,
                                          creditCardPredicate: options.creditCardPredicate) { [weak self] result, _, _ in
                    guard let self = self, isValid(operationId) else {
                        // Skip next stage if operation is no longer valid
                        completion(false)
                        return
                    }
                    self.runTextScannerWithCancellation(
                        inputURL: inputURL,
                        options: options,
                        operationId: operationId,
                        isValid: isValid,
                        completion: completion)
                }
            } else {
                runTextScannerWithCancellation(
                    inputURL: inputURL,
                    options: options,
                    operationId: operationId,
                    isValid: isValid,
                    completion: completion
                )
            }
        }
    
    private func runTextScannerWithCancellation(
        inputURL: URL,
        options: SessionReplayOptions,
        operationId: UUID,
        isValid: @escaping (UUID) -> Bool,
        completion: @escaping (Bool) -> Void) {
            
            // Check if operation is still valid
            guard isValid(operationId) else {
                completion(false)
                return
            }
            
            // Run Text Scanner if enabled
            if isTextScannerEnabled {
                textScanner.processImage(at: inputURL, maskText: options.maskText) { [weak self] result, _, _ in
                    guard let self = self, isValid(operationId) else {
                        // Skip next stage if operation is no longer valid
                        completion(false)
                        return
                    }
                    self.runFaceScannerWithCancellation(
                        inputURL: inputURL,
                        options: options,
                        operationId: operationId,
                        isValid: isValid,
                        completion: completion
                    )
                }
            } else {
                runFaceScannerWithCancellation(
                    inputURL: inputURL,
                    options: options,
                    operationId: operationId,
                    isValid: isValid,
                    completion: completion
                )
            }
        }
    
    private func runFaceScannerWithCancellation(
        inputURL: URL,
        options: SessionReplayOptions,
        operationId: UUID,
        isValid: @escaping (UUID) -> Bool,
        completion: @escaping (Bool) -> Void) {
            
            // Check if operation is still valid
            guard isValid(operationId) else {
                completion(false)
                return
            }
#if targetEnvironment(simulator)
            // Skip face scanning on the simulator
            Log.e("Skipping FaceScanner as we are running on the simulator")
            runClickScannerWithCancellation(
                inputURL: inputURL,
                options: options,
                operationId: operationId,
                isValid: isValid,
                completion: completion)
#else
            // Run Face Scanner if enabled
            if isFaceScannerEnabled {
                faceScanner.processImage(at: inputURL) { [weak self] result in
                    guard let self = self, isValid(operationId) else {
                        // Skip next stage if operation is no longer valid
                        completion(false)
                        return
                    }
                    
                    Log.d("FaceScanner completed successfully.")
                    self.runClickScannerWithCancellation(
                        inputURL: inputURL,
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
                    options: options,
                    operationId: operationId,
                    isValid: isValid,
                    completion: completion)
            }
#endif
        }
    
    private func runClickScannerWithCancellation(
        inputURL: URL,
        options: SessionReplayOptions,
        operationId: UUID,
        isValid: @escaping (UUID) -> Bool,
        completion: @escaping (Bool) -> Void) {
            
            // Check if operation is still valid
            guard isValid(operationId) else {
                completion(false)
                return
            }
            // TBD: need to have the x, y from Coralogix SDK
            clickScanner.processImage(at: inputURL, x: 100, y: 100) { result in
                guard isValid(operationId) else {
                    // Skip next stage if operation is no longer valid
                    completion(false)
                    return
                }
                completion(result)
            }
        }
}
