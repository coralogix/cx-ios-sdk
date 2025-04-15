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
                
                DispatchQueue.global(qos: .userInitiated).async {
                    self.pipeline.runPipeline(inputURL: inputURL, options: sessionReplayOptions) { success in
                        DispatchQueue.main.async {
                            if success {
                                Log.d("Pipeline completed successfully!")
                            } else {
                                Log.e("Pipeline encountered an error.")
                            }
                        }
                    }
                }
            }
    }
}
