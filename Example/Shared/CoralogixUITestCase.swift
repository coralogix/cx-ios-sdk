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
    var sdkFlushDelay: TimeInterval  { isCI ?  5.0 :  1.0 }
    var networkDelay: TimeInterval   { isCI ?  3.0 :  1.5 }

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
}
