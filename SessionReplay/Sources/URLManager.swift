//
//  URLManager.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 24/12/2024.
//

import Foundation
import Combine
import CoralogixInternal

struct URLEntry {
    let url: URL
    let timestamp: TimeInterval
    let completion: ((Bool, TimeInterval) -> Void)?
}

class URLManager: ObservableObject {
    @Published private(set) var savedURLs: [URLEntry] = []
    private let maxUrlsToKeep: Int
        
    init(maxUrlsToKeep: Int = 100) {
        self.maxUrlsToKeep = max(1, maxUrlsToKeep)
    }
    
    func addURL(_ url: URL, timestamp: TimeInterval, completion: ((Bool,TimeInterval) -> Void)? = nil) {
        DispatchQueue.main.async {
            self.savedURLs.append(URLEntry(url: url,
                                      timestamp: timestamp,
                                      completion: completion))
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
                        options: sessionReplayOptions,
                        operationId: operationId,
                        isValid: { [weak self] id in
                            return self?.currentOperationId == id
                        },
                        completion: { isSuccess in
                            DispatchQueue.main.async {
                                // Only log completion if this is still the current operation
                                if self.currentOperationId == operationId {
                                    if isSuccess {
                                        Log.d("Pipeline completed successfully for URL: \(inputURL.lastPathComponent)")
                                    } else {
                                        Log.e("Pipeline encountered an error for URL: \(inputURL.lastPathComponent)")
                                    }
                                    completion?(isSuccess, timestamp)
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
