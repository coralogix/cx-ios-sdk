//
//  URLManager.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 24/12/2024.
//

import Foundation
import Combine
import CoralogixInternal
import CoreImage

typealias URLProcessingCompletion = (CIImage?, TimeInterval, String) -> Void

struct URLEntry {
    let url: URL
    let timestamp: TimeInterval
    let screenshotId: String
    let screenshotData: Data
    let completion: URLProcessingCompletion?
    let point: CGPoint?
}

class URLManager: ObservableObject {
    @Published private(set) var savedURLs: [URLEntry] = []
    private let maxUrlsToKeep: Int
        
    init(maxUrlsToKeep: Int = 100) {
        self.maxUrlsToKeep = max(1, maxUrlsToKeep)
    }
    
    func addURL(urlEntry: URLEntry) {
        DispatchQueue.main.async {
            self.savedURLs.append(urlEntry)
            if self.savedURLs.count > self.maxUrlsToKeep {
                self.savedURLs.removeFirst(self.savedURLs.count - self.maxUrlsToKeep)
            }
        }
    }
}

class URLObserver {
    private var cancellable: AnyCancellable?
    private let pipeline = ScannerPipeline()
    private var sessionReplayOptions: SessionReplayOptions?
    private var currentOperationId: UUID? // Track current operation
    
    init(urlManager: URLManager, sessionReplayOptions: SessionReplayOptions?) {
        self.sessionReplayOptions = sessionReplayOptions
        cancellable = urlManager.$savedURLs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedEntries in
                
                guard let self = self,
                      let lastEntry = updatedEntries.last,
                      let sessionReplayOptions = self.sessionReplayOptions else { return }
                
                let inputURL = lastEntry.url
                let completion = lastEntry.completion
                let timestamp = lastEntry.timestamp
                let screenshotId = lastEntry.screenshotId
                let screenshotData = lastEntry.screenshotData
                let point = lastEntry.point
                
                if let patterns = sessionReplayOptions.maskText {
                    self.pipeline.isTextScannerEnabled = !patterns.isEmpty
                }
                self.pipeline.isFaceScannerEnabled = sessionReplayOptions.maskFaces
                self.pipeline.isImageScannerEnabled = sessionReplayOptions.maskImages
                
                // Generate a new operation ID for this pipeline run
                let operationId = UUID()
                self.currentOperationId = operationId
                
                let processingQueue = DispatchQueue(label: "com.coralogix.urlProcessing", qos: .userInitiated)
                processingQueue.async {
                    self.pipeline.runPipelineWithCancellation(
                        inputURL: inputURL,
                        screenshotData: screenshotData,
                        options: sessionReplayOptions,
                        operationId: operationId,
                        isValid: { [weak self] id in
                            return self?.currentOperationId == id
                        },
                        tapPoint: point,
                        completion: { ciImage in
                            DispatchQueue.main.async {
                                // Only log completion if this is still the current operation
                                if self.currentOperationId == operationId {
                                    if ciImage != nil {
                                        Log.d("Pipeline completed successfully for URL: \(inputURL.lastPathComponent)")
                                    } else {
                                        Log.e("Pipeline encountered an error for URL: \(inputURL.lastPathComponent)")
                                    }
                                    completion?(ciImage, timestamp, screenshotId)
                                }
                            }
                        }
                    )
                }
            }
    }
    
    deinit {
        cancellable?.cancel()
    }
}
