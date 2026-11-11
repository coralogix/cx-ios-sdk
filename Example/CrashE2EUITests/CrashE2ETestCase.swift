//
//  CrashE2ETestCase.swift
//  CrashE2EUITests
//
//  Shared steps of the crash e2e suite, like Android's CrashE2ETest: an endpoint per test, a fresh
//  install at the first launch (`reset`), launching scenarios, crashing and relaunching, and reading
//  back what arrived and what the app still keeps.
//

import XCTest

class CrashE2ETestCase: XCTestCase {
    var app: XCUIApplication!
    var endpoint: Endpoint!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The app crashes on purpose; XCTest reports that as an issue. Only that issue is expected,
        // in either of its forms: an app that dies while XCTest is still bringing it up is reported
        // as a background assertion XCTest could not get for it, rather than as a crash.
        let crashes = XCTExpectedFailure.Options()
        crashes.isStrict = false
        crashes.issueMatcher = { issue in
            let description = issue.compactDescription
            return description.contains("crashed") || description.contains("Failed to get background assertion for target app")
        }
        XCTExpectFailure("the app under test crashes on purpose", options: crashes)
        endpoint = try Endpoint()
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        endpoint?.stop()
    }

    // MARK: - Scenarios

    /// The scenario JSON for `fields` over the defaults: this test's endpoint.
    func scenario(_ fields: [String: Any]) -> String {
        var scenario: [String: Any] = ["proxyUrl": endpoint.url]
        fields.forEach { scenario[$0.key] = $0.value }
        let data = try? JSONSerialization.data(withJSONObject: scenario)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Launches the app with `fields`, and waits for its first screen and its actions.
    @discardableResult
    func launch(_ fields: [String: Any] = [:], waitForActions: Bool = true) -> XCUIApplication {
        app.launchEnvironment["CX_E2E_SCENARIO"] = scenario(fields)
        app.launch()
        if waitForActions {
            XCTAssertTrue(app.staticTexts["e2e.ready"].waitForExistence(timeout: 20), "the scenario's actions did not finish")
            XCTAssertTrue(app.staticTexts["e2e.ready"].label == "ready" || waitFor { self.app.staticTexts["e2e.ready"].label == "ready" })
        }
        return app
    }

    /// A first launch on a fresh install that ends in `crash` (a crash kind) after `before` actions.
    func crash(_ kind: String, _ fields: [String: Any] = [:], fresh: Bool = true) {
        crash(kind, before: [], fields, fresh: fresh)
    }

    func crash(_ kind: String, before: [String], _ fields: [String: Any] = [:], fresh: Bool = true) {
        var scenario = fields
        scenario["hooks"] = (fresh ? ["reset"] : []) + (fields["hooks"] as? [String] ?? [])
        // Live events go out in batches every 2 s: let those of `before` leave before the crash.
        scenario["actions"] = ["wait:1000"] + before + (before.isEmpty ? [] : ["wait:3000"]) + ["crash:\(kind)"]
        launch(scenario, waitForActions: false)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "the app did not crash")
    }

    /// Launches again, as the user opening the app after the crash.
    func relaunch(_ fields: [String: Any] = [:]) {
        launch(fields)
    }

    /// Ends the app as the system's watchdog would, or a user swiping it away.
    func kill() {
        app.terminate()
    }

    /// Leaves a crash on disk with its delivery record written: crashes, then a launch whose send
    /// gets no answer is ended mid-upload.
    /// Every crash request goes unanswered meanwhile, so crashes stored before are kept too.
    func storeCrash(_ kind: String = "exception", _ fields: [String: Any] = [:], fresh: Bool = true) {
        endpoint.answerCrashes([], then: .noAnswer)
        crash(kind, fields, fresh: fresh)
        let before = endpoint.crashRequests.count
        launch(fields, waitForActions: false)
        XCTAssertTrue(waitFor(timeout: 30) { self.endpoint.crashRequests.count > before }, "the stored crash was not sent")
        kill()
        endpoint.answerCrashes([])
    }

    /// A hang the launch ends during: detected (and its marker written) before the kill. The live
    /// ANR gets no answer unless `liveDelivered`, so only the next launch can report it.
    func endDuringHang(_ fields: [String: Any] = [:], fresh: Bool = true, liveDelivered: Bool = false) {
        if !liveDelivered { endpoint.answerLive(.noAnswer) }
        var scenario = fields
        scenario["hooks"] = (fresh ? ["reset"] : []) + (fields["hooks"] as? [String] ?? [])
        scenario["actions"] = ["wait:1000", "hangForever"]
        launch(scenario, waitForActions: false)
        settle(liveDelivered ? 12 : 8)
        kill()
        endpoint.answerLive(.ok)
    }

    /// Every ANR event received: the live ones (`is_crash` false) and recovered ones.
    var anrs: [[String: Any]] { endpoint.events.filter { errorType($0) == "ANR" } }

    // MARK: - Reading back

    /// Waits until the endpoint has `count` crash events, and returns them.
    @discardableResult
    func awaitCrashes(_ count: Int, timeout: TimeInterval = 30) -> [[String: Any]] {
        XCTAssertTrue(waitFor(timeout: timeout) { self.endpoint.crashes.count >= count },
                      "expected \(count) crash event(s), got \(endpoint.crashes.count) in \(endpoint.requests.count) request(s); stored: \(storedCrashes())")
        return endpoint.crashes
    }

    /// Lets `seconds` pass, for asserting that nothing (more) arrives.
    func settle(_ seconds: TimeInterval = 8) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    /// The crashes the app keeps: id, kind and counted failures.
    func storedCrashes() -> [[String: Any]] {
        let label = app.staticTexts["e2e.store"]
        guard label.waitForExistence(timeout: 10) else { return [] }
        // The screen refreshes every half second.
        settle(1)
        let text = app.staticTexts["e2e.store"].label
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]] ?? []
    }

    func sessionId() -> String {
        app.staticTexts["e2e.session"].label
    }

    func waitFor(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        return condition()
    }

    // MARK: - Event fields

    func error(_ event: [String: Any]) -> [String: Any] { event["error_context"] as? [String: Any] ?? [:] }
    func message(_ event: [String: Any]) -> String? { error(event)["error_message"] as? String }
    func errorType(_ event: [String: Any]) -> String? { error(event)["error_type"] as? String }
    func exceptionType(_ event: [String: Any]) -> String? { error(event)["exception_type"] as? String }
    func threads(_ event: [String: Any]) -> [[[String: Any]]] { error(event)["threads"] as? [[[String: Any]]] ?? [] }
    func session(_ event: [String: Any]) -> String? { (event["session_context"] as? [String: Any])?["session_id"] as? String }
    func view(_ event: [String: Any]) -> String? { (event["view_context"] as? [String: Any])?["view"] as? String }
    func appVersion(_ event: [String: Any]) -> String? { (event["version_metadata"] as? [String: Any])?["app_version"] as? String }
    func errorCount(_ event: [String: Any]) -> Int? { (event["snapshot_context"] as? [String: Any])?["errorCount"] as? Int }
    func traceId(_ event: [String: Any]) -> String? { event["traceId"] as? String }
    func isCrash(_ event: [String: Any]) -> Bool? { error(event)["is_crash"] as? Bool }

    /// The fault a write through a near-null pointer raises: the kernel names it by whether the
    /// page is mapped, which differs between devices and OS versions.
    static let nullWriteMessages = ["SIGSEGV (SEGV_MAPERR)", "SIGSEGV (SEGV_ACCERR)"]
    func failedUploads(_ stored: [String: Any]) -> Int? { stored["failedUploads"] as? Int }
}
