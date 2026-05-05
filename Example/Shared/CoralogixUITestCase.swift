//
//  CoralogixUITestCase.swift
//  Shared base class for the UIKit and SwiftUI demo-app UI test bundles.
//

import XCTest

class CoralogixUITestCase: XCTestCase {

    var app: XCUIApplication!
    var isCI = false

    var elementTimeout: TimeInterval { isCI ? 15.0 : 10.0 }
    var shortDelay: TimeInterval     { isCI ?  0.5 :  0.3 }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let env = ProcessInfo.processInfo.environment
        isCI = env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" || env["CONTINUOUS_INTEGRATION"] == "true"
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment["CX_BATCH_SCHEDULE_DELAY_MS"] = "100"
        clearValidationData()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        let stopped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue),
            object: app
        )
        wait(for: [stopped], timeout: 5.0)
        app = nil
        try super.tearDownWithError()
    }

    func clearValidationData() {
        try? FileManager.default.removeItem(atPath: "/tmp/coralogix_validation_response.json")
    }

    /// Wait for the host app's `tracesExporter` callback to populate
    /// `/tmp/coralogix_validation_response.json` with at least one log entry.
    /// Replaces the old "navigate to Schema validation → tap Validate → wait
    /// for backend round-trip" flow with a sub-second poll.
    func flushAndValidate(timeout: TimeInterval? = nil) {
        let path = "/tmp/coralogix_validation_response.json"
        let predicate = NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return false
            }
            return !arr.isEmpty
        }
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        wait(for: [exp], timeout: timeout ?? (isCI ? 5.0 : 3.0))
    }
}
