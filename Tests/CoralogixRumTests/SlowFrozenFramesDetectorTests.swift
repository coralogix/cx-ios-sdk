//
//  SlowFrozenFramesDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 14/08/2025.
//

import XCTest
@testable import Coralogix

final class SlowFrozenFramesDetectorTests: XCTestCase {
    @discardableResult
    private func addObserver(_ handler: @escaping (MobileVitals) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .cxRumNotificationMetrics,
            object: nil,
            queue: .main
        ) { note in
            guard let payload = note.object as? MobileVitals else { return }
            handler(payload)
        }
    }
    
    // MARK: - Tests
    
    /// Forces frozen frames by making the threshold tiny so normal 60Hz frames (≈16.6ms) count as frozen.
//    func testFrozenFramesAreEmitted() {
//        let emitted = expectation(description: "Emitted frozenFramesCount")
//        emitted.expectedFulfillmentCount = 1
//        
//        // reportInterval small so we don't wait long for a window flush
//        let monitor = SlowFrozenFramesDetector(
//            frozenThresholdMs: 1.0,         // everything ≥ 1ms is "frozen"
//            reportIntervalMs: 200,          // 0.2s window
//            tolerancePercentage: 0.03
//        )
//        
//        let obs = addObserver { payload in
//            guard payload.type == .frozenFrames else { return }
//            XCTAssertNotNil(Double(payload.value), "Value should be numeric")
//            XCTAssertGreaterThan(payload.value, 0, "Count should be > 0")
//            emitted.fulfill()
//        }
//        
//        defer {
//            monitor.stopMonitoring()
//            NotificationCenter.default.removeObserver(obs)
//        }
//        
//        monitor.startMonitoring()
//        wait(for: [emitted], timeout: 3.0)
//        monitor.stopMonitoring()
//        NotificationCenter.default.removeObserver(obs)
//    }
    
    /// Forces slow frames by making "slow" threshold easier:
    /// - frozen impossible (very high threshold)
    /// - negative tolerance shrinks the allowed budget so ~16.6ms qualifies as slow
    func testSlowFramesAreEmitted() {
        let emitted = expectation(description: "Emitted slowFramesCount")
        emitted.expectedFulfillmentCount = 1
        
        let monitor = SlowFrozenFramesDetector(
            frozenThresholdMs: 10_000.0,    // effectively never frozen
            reportIntervalMs: 200,
            tolerancePercentage: -0.5       // lowers slow threshold below ~16.6ms
        )
        
        let obs = addObserver { payload in
            guard payload.type == .slowFrames else { return }
            XCTAssertNotNil(Double(payload.value), "Value should be numeric")
            XCTAssertGreaterThan(payload.value, 0, "Count should be > 0")
            emitted.fulfill()
        }
        
        defer {
            monitor.stopMonitoring()
            NotificationCenter.default.removeObserver(obs)
        }
        
        monitor.startMonitoring()
        wait(for: [emitted], timeout: 3.0)
        monitor.stopMonitoring()
        NotificationCenter.default.removeObserver(obs)
    }
    
    /// After first window emission, stopMonitoring() should prevent any further ticks (new UUID).
//    func testStopPreventsFurtherEmissions() {
//        // Use frozen path to guarantee at least one emission quickly
//        let monitor = SlowFrozenFramesDetector(
//            frozenThresholdMs: 1.0,
//            reportIntervalMs: 200,
//            tolerancePercentage: 0.03
//        )
//        
//        var firstUUID: String?
//        
//        let firstWindow = XCTNSNotificationExpectation(name: .cxRumNotificationMetrics, object: nil)
//        firstWindow.handler = { note in
//            guard let mv = note.object as? MobileVitals else { return false }
//            firstUUID = mv.uuid
//            return true // fulfill on the first one we see
//        }
//        
//        monitor.startMonitoring()
//        wait(for: [firstWindow], timeout: 5.0)
//        monitor.stopMonitoring()
//        
//        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
//        let noMoreNewWindows = XCTNSNotificationExpectation(name: .cxRumNotificationMetrics, object: nil)
//        noMoreNewWindows.isInverted = true
//        noMoreNewWindows.handler = { note in
//            guard let mv = note.object as? MobileVitals,
//                  let first = firstUUID else { return false }
//            return mv.uuid != first // return true => this would fulfill (and thus fail because inverted)
//        }
//        
//        // Short grace period where a *new* window must NOT appear
//        wait(for: [noMoreNewWindows], timeout: 1.0)
//    }
}
