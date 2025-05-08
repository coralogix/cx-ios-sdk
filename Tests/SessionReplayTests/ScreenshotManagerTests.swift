//
//  ScreenshotManagerTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 04/05/2025.
//
import XCTest
import CoralogixInternal
@testable import SessionReplay

class ScreenshotManagerTests: XCTestCase {

    func testInitialValues() {
        let manager = ScreenshotManager()
        XCTAssertEqual(manager.page, 0)
        XCTAssertEqual(manager.screenshotCount, 0)
    }

    func testScreenshotCountIncrements() {
        let manager = ScreenshotManager()
        manager.takeScreenshot()
        XCTAssertEqual(manager.screenshotCount, 1)
        XCTAssertEqual(manager.page, 0)
    }

    func testPageIncrementsEveryFiveScreenshots() {
        let manager = ScreenshotManager()
        for _ in 1...40 {
            manager.takeScreenshot()
        }
        XCTAssertEqual(manager.screenshotCount, 40)
        XCTAssertEqual(manager.page, 2)
    }

    func testResetSession() {
        let manager = ScreenshotManager()
        for _ in 1...7 {
            manager.takeScreenshot()
        }
        manager.resetSession()
        XCTAssertEqual(manager.page, 0)
        XCTAssertEqual(manager.screenshotCount, 0)
    }
}
