//
//  CXSlowRenderingDetectorTests.swift
//
//
//  Created by Tomer Har Yoffi on 08/09/2024.
//

import XCTest
@testable import Coralogix

final class CXSlowRenderingDetectorTests: XCTestCase, CXSlowRenderingDetectorDelegate {
    
    class MockDisplayLink: CXDisplayLinkProtocol {
        var timestamp: CFTimeInterval = 0
        var callback: ((CFTimeInterval) -> Void)?
        
        func simulateFrame(elapsedTime: CFTimeInterval) {
            timestamp += elapsedTime
            callback?(timestamp)
        }
    }
    
    var cxSlowRenderingDetector: CXSlowRenderingDetector!
    var mockDisplayLink: MockDisplayLink!
    var cxSlowFramesDetectedExpectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        cxSlowRenderingDetector = CXSlowRenderingDetector()
        cxSlowRenderingDetector.delegate = self
        
        // Set up the mock display link and directly bind the callback to the checkFrameRendering method
        mockDisplayLink = MockDisplayLink()
        mockDisplayLink.callback = { [weak self] timestamp in
            guard let self = self else { return }
            self.cxSlowRenderingDetector.checkFrameRendering(displayLink: self.mockDisplayLink)
        }
    }
    
    override func tearDown() {
        cxSlowRenderingDetector = nil
        mockDisplayLink = nil
        super.tearDown()
    }
    
    // Delegate method to capture slow frame detection
    func didDetectSlowFrames(consecutiveSlowFrames: Int) {
        XCTAssertEqual(consecutiveSlowFrames, 5, "Expected 5 consecutive slow frames detected")
        cxSlowFramesDetectedExpectation?.fulfill()  // Fulfill expectation
    }

    func testSlowFramesDetected() {
        cxSlowFramesDetectedExpectation = expectation(description: "Expected 5 consecutive slow frames detected")

        // Start monitoring
        cxSlowRenderingDetector.startMonitoring()

        // Simulate 5 consecutive slow frames (0.05 seconds per frame, slower than the 1/60 threshold)
        for _ in 1...5 {
            mockDisplayLink.simulateFrame(elapsedTime: 0.05)  // 50 milliseconds per frame
        }
        // Wait for the expectation to be fulfilled
        wait(for: [cxSlowFramesDetectedExpectation!], timeout: 1.0)
    }
    
    func testResetOnFastFrame() {
        // Simulate starting the monitoring process
        cxSlowRenderingDetector.startMonitoring()
        
        // Simulate 4 slow frames
        for _ in 1...4 {
            mockDisplayLink.simulateFrame(elapsedTime: 0.05)
        }
        
        // Simulate 1 fast frame (below the threshold)
        mockDisplayLink.simulateFrame(elapsedTime: 0.01)
        
        // Expect the slow frame counter to reset after the fast frame
        XCTAssertEqual(cxSlowRenderingDetector.consecutiveSlowFrames, 0, "Expected slow frame counter to reset after fast frame")
    }
}
