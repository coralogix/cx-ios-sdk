//
//  CoralogixUITestCase.swift
//  Shared base class for the UIKit and SwiftUI demo-app UI test bundles.
//

import XCTest

class CoralogixUITestCase: XCTestCase {

    var app: XCUIApplication!
    var isCI = false

    var elementTimeout: TimeInterval { isCI ? 15.0 : 10.0 }
    var shortDelay: TimeInterval     { isCI ?  2.0 :  1.0 }
    var sdkFlushDelay: TimeInterval  { isCI ? 10.0 :  5.0 }
    var networkDelay: TimeInterval   { isCI ?  8.0 :  3.0 }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let env = ProcessInfo.processInfo.environment
        isCI = env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" || env["CONTINUOUS_INTEGRATION"] == "true"
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
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
