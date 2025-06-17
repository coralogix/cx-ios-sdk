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

typealias URLProcessingCompletion = (CIImage?, URLEntry?) -> Void

struct URLEntry {
    let url: URL
    let timestamp: TimeInterval
    let screenshotId: String
    let segmentIndex: Int
    let page: String
    let screenshotData: Data
    let point: CGPoint?
    let completion: URLProcessingCompletion?
    var finalImage: CIImage? = nil
    var ciImage: CIImage? {
        guard let originalImage = CIImage(data: screenshotData) else {
            Log.e("Failed to decode screenshot data into CIImage.")
            return nil
        }
        return originalImage
    }
}

class URLManager: ObservableObject {
    @Published private(set) var lastEntry: URLEntry?
    
    func addURL(urlEntry: URLEntry) {
        DispatchQueue.main.async {
            self.lastEntry = urlEntry
        }
    }
}

class URLObserver {
    private var cancellable: AnyCancellable?
    private let pipeline = ScannerPipeline()
    
    init(urlManager: URLManager, sessionReplayOptions: SessionReplayOptions?) {
        cancellable = urlManager.$lastEntry
            .compactMap { $0 }
            .sink { [weak self] entry in
                let processingQueue = DispatchQueue(label: Keys.queueUrlProcessing.rawValue, qos: .userInitiated)
                processingQueue.async {
                    guard let self = self,
                          let sessionReplayOptions = sessionReplayOptions else {
                        Log.e("Invalid entry received")
                        return
                    }
                                        
                    self.pipeline.runPipeline(
                        options: sessionReplayOptions,
                        urlEntry: entry,
                        completion: { ciImage, urlEntry in
                            DispatchQueue.main.async {
                                if ciImage != nil {
                                    if let url = urlEntry?.url {
                                        Log.d("Pipeline completed successfully for URL: \(url.lastPathComponent)")
                                    }
                                } else {
                                    if let url = urlEntry?.url {
                                        Log.e("Pipeline encountered an error for URL: \(url.lastPathComponent)")
                                    }
                                }
                                urlEntry?.completion?(ciImage, urlEntry)
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
