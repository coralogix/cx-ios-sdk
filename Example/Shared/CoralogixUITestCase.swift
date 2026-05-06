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

    // MARK: - Marshal-field span capture (Phase 2.2 v3)

    /// Reads the host app's marshal text field and returns the captured
    /// interaction events as flat dicts. Each event has the keys produced by
    /// `InteractionContext.payload` — typically:
    ///   - `event_name`: `"click" | "scroll" | "swipe"`
    ///   - `scroll_direction`: `"up" | "down" | "left" | "right"` (when applicable)
    ///   - `target_element`: resolveTargetName output or UIKit class name
    ///   - `element_classes`: UIKit class name (always present)
    ///   - `element_id`: accessibilityIdentifier (when set)
    ///   - `target_element_inner_text`: captured text (when shouldSendText permits)
    ///
    /// Polls the marshal field every 0.25s until it contains a non-empty
    /// JSON array, or `timeout` elapses. Returns `nil` on timeout.
    ///
    /// Manual polling instead of `XCTNSPredicateExpectation` because the
    /// expectation's predicate evaluates `field.value as? String`, and
    /// `XCUIElement.value` *raises* "no matching snapshot" rather than
    /// returning nil before the host app has installed the field. Checking
    /// `field.exists` first sidesteps the throw.
    func marshaledInteractionEvents(timeout: TimeInterval? = nil) -> [[String: Any]]? {
        let identifier = "coralogix.uitesting.marshal"
        let totalTimeout = timeout ?? (isCI ? 8.0 : 4.0)
        let deadline = Date().addingTimeInterval(totalTimeout)
        let field = app.textFields[identifier]

        while Date() < deadline {
            if field.exists,
               let value = field.value as? String,
               !value.isEmpty,
               let data = value.data(using: .utf8),
               let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               !events.isEmpty {
                return events
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    /// Returns true when at least one marshaled event matches all the
    /// supplied (non-nil) criteria. Mirrors `hasInteractionEvent` in the
    /// individual test files but consumes the flat marshaled shape.
    func hasMarshaledEvent(in events: [[String: Any]],
                           eventName: String,
                           direction: String? = nil,
                           targetElement: String? = nil,
                           elementId: String? = nil) -> Bool {
        for event in events {
            guard (event["event_name"] as? String) == eventName else { continue }
            if let dir = direction, (event["scroll_direction"] as? String) != dir { continue }
            if let te = targetElement, (event["target_element"] as? String) != te { continue }
            if let eid = elementId, (event["element_id"] as? String) != eid { continue }
            return true
        }
        return false
    }
}
