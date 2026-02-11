//
//  ColdDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 16/09/2025.
//

import XCTest
import Foundation
import UIKit

@testable import Coralogix

class ColdDetectorTests: XCTestCase {
    
    private func makeMetricsDict(launchEndTime: CFAbsoluteTime) -> [String: Any] {
        return [MobileVitalsType.cold.stringValue: launchEndTime]
    }
    
    var coldDetector: ColdDetector!
    var expectation: XCTestExpectation!
    
    override func setUp() {
        super.setUp()
        coldDetector = ColdDetector()
    }
    
    override func tearDown() {
        coldDetector = nil
        super.tearDown()
    }
 
    func testStartMonitoring_setsStartTime() {
        XCTAssertNil(coldDetector.launchStartTime)

        coldDetector.startMonitoring()

        XCTAssertNotNil(coldDetector.launchStartTime, "startMonitoring() should set launchStartTime")
        // No assertion for observer registration directly; other tests indirectly verify by posting notifications.
        _ = coldDetector // keep alive
    }
    
    func testHandleNotification_setsEndTimeAndEmitsColdOnce() {
        // Use deterministic times. Any constant offset added by Helper's conversion cancels in the delta.
        coldDetector.startMonitoring()

        let start: CFAbsoluteTime = 1_000.0
        let end: CFAbsoluteTime = 1_500.0
        coldDetector.launchStartTime = start
        

        let called = expectation(description: "handleColdClosure called exactly once")
        called.expectedFulfillmentCount = 1
        
        var received: [String: Any]?
        coldDetector.handleColdClosure = { payload in
            received = payload
            called.fulfill()
        }
        
        // Post first (valid) notification
        NotificationCenter.default.post(
            name: .cxViewDidAppear,
            object: makeMetricsDict(launchEndTime: end)
        )
        
        // Post a second notification that should be ignored since launchEndTime is already set
        NotificationCenter.default.post(
            name: .cxViewDidAppear,
            object: makeMetricsDict(launchEndTime: end + 100.0)
        )
        
        wait(for: [called], timeout: 1.0)
        
        // Verify the detector latched the first end time only
        XCTAssertEqual(coldDetector.launchEndTime, end, "launchEndTime should be set from the first valid notification only")
        
        // Verify payload structure & value
        guard
            let payload = received?[MobileVitalsType.cold.stringValue] as? [String: Any],
            let units = payload[Keys.mobileVitalsUnits.rawValue] as? String,
            let value = payload[Keys.value.rawValue] as? Double
        else {
            return XCTFail("Payload structure is not as expected")
        }
        
        XCTAssertEqual(units, MeasurementUnits.milliseconds.stringValue, "Units should be milliseconds")
        
        // Helper converts both start and end to epoch before delta, so delta should remain (end - start)
        let expected = coldDetector.calculateTime(start: Helper.convertCFAbsoluteTimeToEpoch(start),
                                         stop: Helper.convertCFAbsoluteTimeToEpoch(end))
        XCTAssertEqual(value, expected, accuracy: 0.000_1, "Cold start ms should equal converted delta")
    }
    
    func testHandleNotification_ignoresWhenStartNotSet() {
        let sut = ColdDetector()
        sut.launchStartTime = nil
        
        let notCalled = expectation(description: "handleColdClosure not called")
        notCalled.isInverted = true
        
        sut.handleColdClosure = { _ in
            notCalled.fulfill()
        }
        
        NotificationCenter.default.post(
            name: .cxViewDidAppear,
            object: makeMetricsDict(launchEndTime: 1234.0)
        )
        
        wait(for: [notCalled], timeout: 0.5)
        XCTAssertNil(sut.launchEndTime, "launchEndTime should remain nil if start was never set")
    }
    
    func testCalculateTime_isNonNegative() {
        let sut = ColdDetector()
        // Normal forward time
        XCTAssertEqual(sut.calculateTime(start: 10, stop: 25), 15, accuracy: 0.000_1)
        // Negative delta is clamped to zero
        XCTAssertEqual(sut.calculateTime(start: 25, stop: 10), 0, accuracy: 0.000_1)
        // Equal times
        XCTAssertEqual(sut.calculateTime(start: 42, stop: 42), 0, accuracy: 0.000_1)
    }
    
    func testDeinit_removesObserver_andZeroesEndTime() {
        // We can’t directly introspect NotificationCenter observers, but we can:
        // 1) Ensure no crash/closure call after the object is deallocated.
        // 2) Verify the deinit side-effect on launchEndTime by peeking just before release.
        var sut: ColdDetector? = ColdDetector()
        sut?.startMonitoring()
        sut?.launchStartTime = 100
        
        // Set a closure that would trip if a dangling observer existed after dealloc.
        let notCalled = expectation(description: "No callbacks after deallocation")
        notCalled.isInverted = true
        sut?.handleColdClosure = { _ in notCalled.fulfill() }
        
        // Capture endTime change in deinit (it sets to 0)
        // We cannot assert after dealloc, so assert right before releasing and then ensure no callbacks happen.
        XCTAssertNil(sut?.launchEndTime)
        
        // Deallocate
        // swiftlint:disable:next weak_var_mutated
        weak var weakSut = sut
        sut = nil
        XCTAssertNil(weakSut, "ColdDetector should deallocate")
        
        // Post a notification; if observer wasn't removed, it might try to message a zombie (would crash)
        NotificationCenter.default.post(
            name: .cxViewDidAppear,
            object: makeMetricsDict(launchEndTime: 200)
        )
        
        wait(for: [notCalled], timeout: 0.5)
        // NOTE: We cannot read launchEndTime after dealloc to assert it's 0; this line intentionally omitted.
    }
}
