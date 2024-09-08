//
//  CXSlowRenderingDetector.swift
//
//
//  Created by Coralogix DEV TEAM on 08/09/2024.
//

import UIKit

protocol CXDisplayLinkProtocol {
    var timestamp: CFTimeInterval { get }
}

extension CADisplayLink: CXDisplayLinkProtocol {}

protocol CXSlowRenderingDetectorDelegate: AnyObject {
    func didDetectSlowFrames(consecutiveSlowFrames: Int)
}

public class CXSlowRenderingDetector {
    private var displayLink: CXDisplayLinkProtocol?
    private var lastTimestamp: CFTimeInterval = 0

    // Frame threshold in seconds (1/60 for 60 FPS)
    private let frameThreshold: CFTimeInterval = 1.0 / 60.0

    // Consecutive slow frames counter
    internal var consecutiveSlowFrames = 0
    private let slowFrameTolerance = 5 // Number of consecutive slow frames before logging

    // Add delegate to notify when slow frames are detected
    weak var delegate: CXSlowRenderingDetectorDelegate?
    
    public func startMonitoring() {
        displayLink = CADisplayLink(target: self, selector: #selector(checkFrameRendering))
        (displayLink as? CADisplayLink)?.add(to: .main, forMode: .common)
    }

    public func stopMonitoring() {
        (displayLink as? CADisplayLink)?.invalidate()
        displayLink = nil
    }
    
    @objc func checkFrameRendering(displayLink: CADisplayLink) {
        checkFrameRendering(displayLink: displayLink as CXDisplayLinkProtocol)
    }

    // This method uses the protocol to make it testable
    func checkFrameRendering(displayLink: CXDisplayLinkProtocol) {

        guard lastTimestamp > 0 else {
            lastTimestamp = displayLink.timestamp
            return
        }

        let elapsed = displayLink.timestamp - lastTimestamp
        lastTimestamp = displayLink.timestamp

        // If a frame takes longer than the threshold, increment the slow frame counter
        if elapsed > frameThreshold {
            consecutiveSlowFrames += 1
        } else {
            // Reset the counter if a fast frame is rendered
            consecutiveSlowFrames = 0
        }

        // Trigger handling after a certain number of consecutive slow frames
        if consecutiveSlowFrames >= slowFrameTolerance {
            delegate?.didDetectSlowFrames(consecutiveSlowFrames: consecutiveSlowFrames)
            handleSlowFrame(elapsed: elapsed)
            consecutiveSlowFrames = 0 // Reset the counter after logging
        }
    }

    private func handleSlowFrame(elapsed: CFTimeInterval) {
        // Handle slow frame rendering (e.g., log, notify, etc.)
        Log.d("[Matric] Consecutive slow frames detected: Last frame took \(elapsed * 1000) milliseconds to render")
    }
}
