//
//  ScreenshotManagerTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 04/05/2025.
//
import XCTest
import CoralogixInternal
@testable import Coralogix

class ScreenshotManagerTests: XCTestCase {
    func testInitialScreenshotLocation() {
        let manager = ScreenshotManager(maxScreenShotsPerPage: 3)
        let location = manager.nextScreenshotLocation
        
        XCTAssertEqual(location.segmentIndex, 1)
        XCTAssertEqual(location.page, 0)
        XCTAssertFalse(location.screenshotId.isEmpty)
    }
    
    func testNextScreenshotLocationInitialPageAndSegment() {
        let manager = ScreenshotManager(maxScreenShotsPerPage: 3)
        manager.screenshotId = "id-1"
        let loc1 = manager.nextScreenshotLocation
        XCTAssertEqual(loc1.segmentIndex, 1)
        XCTAssertEqual(loc1.page, 0)
        XCTAssertEqual(loc1.screenshotId, "id-1")
        
        let loc2 = manager.nextScreenshotLocation
        XCTAssertEqual(loc2.segmentIndex, 2)
        XCTAssertEqual(loc2.page, 0)
    }
    
    func testNextScreenshotLocationPageIncrements() {
        let manager = ScreenshotManager(maxScreenShotsPerPage: 2)
        manager.screenshotId = "id-2"

        _ = manager.nextScreenshotLocation // 1
        _ = manager.nextScreenshotLocation // 2 (max reached)
        let loc3 = manager.nextScreenshotLocation // should reset to 1 and increment page
        
        XCTAssertEqual(loc3.segmentIndex, 1)
        XCTAssertEqual(loc3.page, 1)
    }
    
    func testMultiplePageIncrements() {
        let manager = ScreenshotManager(maxScreenShotsPerPage: 2)
        manager.screenshotId = "id-3"

        var pages: [Int] = []
        var segments: [Int] = []
        
        for _ in 0..<7 {
            let loc = manager.nextScreenshotLocation
            pages.append(loc.page)
            segments.append(loc.segmentIndex)
        }
        
        XCTAssertEqual(pages, [0,0,1,1,2,2,3])
        XCTAssertEqual(segments, [1,2,1,2,1,2,1])
    }
    
    func testRevertScreenshotCounterStepsBackToPageZero() {
        let manager = ScreenshotManager(maxScreenShotsPerPage: 2)
        _ = manager.nextScreenshotLocation // (page 0, 1)
        _ = manager.nextScreenshotLocation // (page 0, 2)
        _ = manager.nextScreenshotLocation // (page 1, 1)

        manager.revertScreenshotCounter()

        // Page 0 is the first page, so reverting the first slot of page 1 belongs on page 0 —
        // stopping at page 1 would strand the counter a whole page ahead of the frames that shipped.
        XCTAssertEqual(manager.page, 0)
        XCTAssertEqual(manager.screenshotCount, 2)
    }

    func testRevertingEveryAllocationReturnsToTheFirstLocation() {
        let manager = ScreenshotManager(maxScreenShotsPerPage: 2)
        for _ in 0..<5 { _ = manager.nextScreenshotLocation } // walks to (page 2, 1)
        for _ in 0..<5 { manager.revertScreenshotCounter() }

        let next = manager.nextScreenshotLocation
        XCTAssertEqual(next.page, 0)
        XCTAssertEqual(next.segmentIndex, 1,
                       "a session whose captures were all rejected must still start at page 0, segment 1")
    }

    func testResetSessionResetsPageAndScreenshotCountAndGeneratesNewId() {
        // Arrange
        let manager = ScreenshotManager()
        let oldId = manager.screenshotId
        
        // Act
        manager.reset()
        
        // Assert
        XCTAssertEqual(manager.page, 0)
        XCTAssertEqual(manager.screenshotCount, 0)
        XCTAssertNotEqual(manager.screenshotId, oldId)
        XCTAssertTrue(manager.screenshotId.allSatisfy { $0.isLowercase || !$0.isLetter })
        XCTAssertEqual(manager.screenshotId.count, 36) // UUID format
    }
}
