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

    // MARK: - In-process span capture (Phase 2.2 v2)

    /// Polls the host app's localhost capture endpoint until at least
    /// `minBatches` OTLP batch(es) have been recorded, or until `timeout`.
    /// Returns the captured batches as JSON strings, or `nil` if the timeout
    /// expired without any data.
    ///
    /// Use this instead of the schema-validator UI flow when a test only
    /// needs to assert that the SDK produced a span — it skips the
    /// (a) `Validate Schema` tap, (b) onrender.com round-trip, (c) on-screen
    /// log readback. Sub-second under typical conditions.
    func fetchCapturedBatches(minBatches: Int = 1, timeout: TimeInterval? = nil) -> [String]? {
        let deadline = Date().addingTimeInterval(timeout ?? (isCI ? 8.0 : 4.0))
        let url = URL(string: "http://127.0.0.1:9999/spans")!
        while Date() < deadline {
            if let batches = pollOnce(url: url), batches.count >= minBatches {
                return batches
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    /// Resets the host app's captured-span store. Call between assertions
    /// when a test wants a clean slice of spans for the next gesture.
    func resetCapturedSpans() {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:9999/spans")!)
        req.httpMethod = "DELETE"
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 1.0)
    }

    private func pollOnce(url: URL) -> [String]? {
        let sem = DispatchSemaphore(value: 0)
        var batches: [String]?
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { sem.signal() }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["batches"] as? [String] else { return }
            batches = arr
        }.resume()
        _ = sem.wait(timeout: .now() + 1.0)
        return batches
    }
}
