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
}
