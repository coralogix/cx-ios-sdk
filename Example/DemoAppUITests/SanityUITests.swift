import XCTest

final class SanityUITests: XCTestCase {
    var app: XCUIApplication!

    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] == "true" ||
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" ||
        ProcessInfo.processInfo.environment["CONTINUOUS_INTEGRATION"] == "true"
    }

    private var elementTimeout: TimeInterval {
        isCI ? 15.0 : 10.0
    }

    private func log(_ message: String) {
        let timestamp = String(format: "%.2f", Date().timeIntervalSince1970)
        print("🕐 [\(timestamp)] \(message)")
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testAppSanity_mainViewAppearsOnLaunch() throws {
        log("🔎 Waiting for 'Main View' navigation bar…")
        let mainNavBar = app.navigationBars["Coralogix Demo"]
        let exists = mainNavBar.waitForExistence(timeout: elementTimeout)
        XCTAssertTrue(exists, "❌ 'Main View' navigation bar should appear on launch")
        log(exists ? "✅ Found 'Main View' navigation bar" : "❌ Did NOT find 'Main View' navigation bar")
    }
}
