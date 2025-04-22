//
//  FPSMonitorTests.swift
//
//
//  Created by Coralogix DEV TRAM on 08/09/2024.
//

import XCTest
@testable import Coralogix

final class FPSMonitorTests: XCTestCase {
    var fpsMonitor: FPSMonitor!
    
    override func setUp() {
        super.setUp()
        fpsMonitor = FPSMonitor()
    }
    
    override func tearDown() {
        fpsMonitor = nil
        super.tearDown()
    }
    
    func testFPSCalculation() {
        // Start monitoring
        fpsMonitor.startMonitoring()
        
        // Manually set the start time to simulate 1 second elapsed time
        fpsMonitor.startTime = CACurrentMediaTime() - 1.0
        
        // Simulate frame updates (60 frames in 1 second)
        for _ in 0..<60 {
            fpsMonitor.trackFrame()
        }
        
        // Stop the monitor and get average FPS
        let averageFPS = fpsMonitor.stopMonitoring()
        
        // Assert that the average FPS is approximately 60
        XCTAssertEqual(averageFPS, 60, accuracy: 1.0, "The average FPS should be approximately 60.")
    }
}

