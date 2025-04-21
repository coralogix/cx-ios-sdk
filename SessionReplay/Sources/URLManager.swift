//
//  URLManager.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 24/12/2024.
//

import Foundation
import Combine
import CoralogixInternal

class URLManager: ObservableObject {
    @Published private(set) var savedURLs: [URL] = []
    
    func addURL(_ url: URL) {
        savedURLs.append(url)
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
            .sink { [weak self] updatedURLs in
                // Perform your desired action here
                Log.d("New URL added. Total count: \(updatedURLs.count)")
                guard let self = self,
                      let inputURL = updatedURLs.last,
                      let sessionReplayOptions = self.sessionReplayOptions else { return }
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
                        completion: { success in
                            DispatchQueue.main.async {
                                // Only log completion if this is still the current operation
                                if self.currentOperationId == operationId {
                                    if success {
                                        Log.d("Pipeline completed successfully for URL: \(inputURL.lastPathComponent)")
                                    } else {
                                        Log.e("Pipeline encountered an error for URL: \(inputURL.lastPathComponent)")
                                    }
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
