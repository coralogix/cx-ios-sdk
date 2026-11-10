//
//  CrashLabUITests.swift
//
//  The Crash Lab screen of the UIKit demo app lists every case of crash-lab/cases.json, and a
//  launch setting changed on it reaches the next launch. What each case does to the SDK is
//  asserted by the crash e2e suite, not here.
//

import XCTest

final class CrashLabUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    /// The settings, the reset row and the cases are cells; the case-id list is a text.
    private func element(_ identifier: String) -> XCUIElement {
        identifier == "crashLab.caseIds" ? app.staticTexts[identifier].firstMatch : app.cells[identifier].firstMatch
    }

    private func openCrashLab() {
        let entry = app.staticTexts["Crash Lab"].firstMatch
        for _ in 0..<8 where !entry.isHittable {
            app.swipeUp()
        }
        entry.tap()
        XCTAssertTrue(element("crashLab.caseIds").waitForExistence(timeout: 10), "the Crash Lab screen did not open")
    }

    /// Scrolls until `identifier` is on screen: a lazy list builds only the rows it shows.
    @discardableResult
    private func reveal(_ identifier: String) -> XCUIElement {
        let target = element(identifier)
        for _ in 0..<10 where !target.exists {
            app.swipeUp()
        }
        return target
    }

    private func value(of identifier: String) -> String? {
        element(identifier).value as? String
    }

    func testCrashLab_listsEveryCaseInCasesJson() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shared/Resources/crash-lab/cases.json")
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        let expected = cases.compactMap { $0["id"] as? String }
        XCTAssertFalse(expected.isEmpty)

        openCrashLab()

        let listed = try XCTUnwrap(value(of: "crashLab.caseIds")).components(separatedBy: ",")
        XCTAssertEqual(listed, expected, "the app bundles an out-of-date cases.json")
        XCTAssertTrue(reveal("crashLab.case.\(expected[0])").exists, "the first case is on screen")
    }

    func testCrashLabSetting_persistsToTheNextLaunch() {
        openCrashLab()
        element("crashLab.reset").tap()
        XCTAssertEqual(value(of: "crashLab.setting.sdkDebug"), "off")

        element("crashLab.setting.sdkDebug").tap()
        XCTAssertEqual(value(of: "crashLab.setting.sdkDebug"), "on")

        app.terminate()
        app.launch()
        openCrashLab()
        XCTAssertEqual(value(of: "crashLab.setting.sdkDebug"), "on", "kept for the next launch")

        element("crashLab.reset").tap()
        XCTAssertEqual(value(of: "crashLab.setting.sdkDebug"), "off")
    }
}
