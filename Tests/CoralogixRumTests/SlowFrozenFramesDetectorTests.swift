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
}
