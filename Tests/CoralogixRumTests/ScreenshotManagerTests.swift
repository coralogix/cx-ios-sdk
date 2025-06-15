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
        manager._screenshotId = "id-1"
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
        manager._screenshotId = "id-2"

        _ = manager.nextScreenshotLocation // 1
        _ = manager.nextScreenshotLocation // 2 (max reached)
        let loc3 = manager.nextScreenshotLocation // should reset to 1 and increment page
        
        XCTAssertEqual(loc3.segmentIndex, 1)
        XCTAssertEqual(loc3.page, 1)
    }
    
    func testMultiplePageIncrements() {
        let manager = ScreenshotManager(maxScreenShotsPerPage: 2)
        manager._screenshotId = "id-3"

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
    
    func testResetSessionResetsPageAndScreenshotCountAndGeneratesNewId() {
        // Arrange
        let manager = ScreenshotManager()
        let oldId = manager._screenshotId
        
        // Act
        manager.resetSession(notification: Notification(name: Notification.Name("ResetSession")))
        
        // Assert
        XCTAssertEqual(manager._page, 0)
        XCTAssertEqual(manager._screenshotCount, 0)
        XCTAssertNotEqual(manager._screenshotId, oldId)
        XCTAssertTrue(manager._screenshotId.allSatisfy { $0.isLowercase || !$0.isLetter })
        XCTAssertEqual(manager._screenshotId.count, 36) // UUID format
    }
}

class ScreenshotLocationTests: XCTestCase {
    func testToPropertiesReturnsCorrectDictionary() {
        // Arrange
        let screenshotLocation = ScreenshotLocation(
            segmentIndex: 3,
            page: 5,
            screenshotId: "abc123"
        )

        // Act
        let properties = screenshotLocation.toProperties()

        // Assert
        XCTAssertEqual(properties[Keys.screenshotId.rawValue] as? String, "abc123")
        XCTAssertEqual(properties[Keys.page.rawValue] as? Int, 5)
        XCTAssertEqual(properties[Keys.segmentIndex.rawValue] as? Int, 3)
    }
}
