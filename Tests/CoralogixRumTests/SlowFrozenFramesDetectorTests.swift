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
    func testFrozenFramesAreEmitted() {
        let emitted = expectation(description: "Emitted frozenFramesCount")
        emitted.expectedFulfillmentCount = 1
        
        // reportInterval small so we don't wait long for a window flush
        let monitor = SlowFrozenFramesDetector(
            frozenThresholdMs: 1.0,         // everything ≥ 1ms is "frozen"
            reportIntervalMs: 200,          // 0.2s window
            tolerancePercentage: 0.03
        )
        
        let obs = addObserver { payload in
            guard payload.type == .frozenFrames else { return }
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
    func testStopPreventsFurtherEmissions() {
        let firstWindow = expectation(description: "First window emitted (any of slow/frozen)")
        let noMore = expectation(description: "No further windows after stop")
        noMore.isInverted = true
        
        // Use frozen path to guarantee at least one emission quickly
        let monitor = SlowFrozenFramesDetector(
            frozenThresholdMs: 1.0,
            reportIntervalMs: 200,
            tolerancePercentage: 0.03
        )
        
        var firstUUID: String?
        var windowTypes = Set<MobileVitalsType>()
        var sawNewUUIDAfterStop = false
        
        let obs = addObserver { payload in
            if firstUUID == nil {
                firstUUID = payload.uuid
            }
            
            if payload.uuid == firstUUID {
                // First window (both metrics could arrive, we just need at least one)
                windowTypes.insert(payload.type)
                // If we've seen both, great; but even one proves the window emitted
                if windowTypes.count >= 1 {
                    firstWindow.fulfill()
                }
            } else {
                // Any metric with a different UUID after we stop would indicate a new window
                sawNewUUIDAfterStop = true
                noMore.fulfill()
            }
        }
        
        monitor.startMonitoring()
        
        // Wait for the first window to emit, then stop and ensure silence
        wait(for: [firstWindow], timeout: 3.0)
        monitor.stopMonitoring()
        
        defer {
            monitor.stopMonitoring()
            NotificationCenter.default.removeObserver(obs)
        }
        
        // Give a small grace period to catch stray next-window posts
        wait(for: [noMore], timeout: 0.7)
        NotificationCenter.default.removeObserver(obs)
        
        XCTAssertFalse(sawNewUUIDAfterStop, "Received metrics from another window after stopMonitoring()")
    }
}
