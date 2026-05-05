//
//  UserInteractionUITests.swift
//  DemoAppSwiftUIUITests
//
//  E2E tests that drive real gestures in the SwiftUI DemoApp and verify that the
//  Coralogix RUM SDK captures scroll, swipe, and tap user-interaction events
//  correctly, then ships them to the backend.
//
//  APPROACH
//  --------
//  1. Launch with --uitesting so SchemaValidationView writes the raw backend
//     response to /tmp/coralogix_validation_response.json.
//  2. Drive gestures that produce specific interaction events.
//  3. Wait for the SDK's export cycle to flush events to the proxy.
//  4. Navigate to Schema validation → tap "Validate Schema" → assert pass.
//  5. Parse the temp file and assert per-event fields
//     (event_name, scroll_direction, target_element).
//
//  KEY JSON PATHS
//  --------------
//  Each log entry may have the interaction_context at:
//    log["text"]["cx_rum"]["interaction_context"]
//  with these keys:
//    "event_name"     : "click" | "scroll" | "swipe"
//    "scroll_direction": "up" | "down" | "left" | "right"  (absent for taps)
//    "target_element" : class name OR custom name from resolveTargetName
//    "element_classes": always the native class name (never overridden)
//    "element_id"     : accessibilityIdentifier (if set on the touched view)
//
//  DIRECTION CONVENTION
//  --------------------
//  The SDK records the FINGER movement direction, not the content-scroll direction:
//    XCUITest swipeDown() → finger moves DOWN → SDK direction "down"
//    XCUITest swipeUp()   → finger moves UP   → SDK direction "up"
//    XCUITest swipeLeft() → finger moves LEFT  → SDK direction "left"
//    XCUITest swipeRight()→ finger moves RIGHT → SDK direction "right"
//

import XCTest

final class UserInteractionUITests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - CI detection

    private var isCI = false

    private var elementTimeout: TimeInterval  { isCI ? 15.0 : 10.0 }
    private var shortDelay: TimeInterval      { isCI ?  2.0 :  1.0 }
    private var sdkFlushDelay: TimeInterval   { isCI ? 10.0 :  5.0 }
    private var networkDelay: TimeInterval    { isCI ?  8.0 :  3.0 }

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()
        let env = ProcessInfo.processInfo.environment
        isCI = env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" || env["CONTINUOUS_INTEGRATION"] == "true"
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment["CX_BATCH_SCHEDULE_DELAY_MS"] = "100"
        clearValidationData()
        print("🟦 🚀 Launching SwiftUI app (CI=\(isCI))")
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        Thread.sleep(forTimeInterval: isCI ? 3.0 : 1.0)
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Compound test (CI-friendly single-run)

    func testAllUserInteractionEvents_combinedSchemaValidation() throws {
        print("🟦 \n========================================")
        print("🟦 🧪 TEST: Combined user interaction E2E (SwiftUI)")
        print("🟦 ========================================\n")

        // ── Phase 1: Scroll events ──
        print("🟦 📜 Phase 1: Scroll gestures…")
        navigateToUserActions()

        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: elementTimeout), "❌ UserActions list not found")

        list.swipeDown()
        Thread.sleep(forTimeInterval: shortDelay)
        list.swipeUp()
        Thread.sleep(forTimeInterval: shortDelay)

        // ── Phase 2: tap instrumentation ──
        print("🟦 👆 Phase 2: Login button tap (tap instrumentation)…")
        let loginButton = app.buttons["loginButton"].firstMatch
        XCTAssertTrue(loginButton.waitForExistence(timeout: elementTimeout),
                      "❌ loginButton not found — check UserActionsView.trackCXTapAction(name: 'Log In')")
        loginButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)

        // ── Phase 3: shouldSendText (sensitiveLabel) ──
        // SwiftUI List buttons expose as .button in XCTest, not .cell like UITableViewCell.
        print("🟦 👆 Phase 3: Sensitive label tap (shouldSendText)…")
        let sensitiveCell = app.buttons["sensitiveLabel"].firstMatch
        XCTAssertTrue(sensitiveCell.waitForExistence(timeout: elementTimeout),
                      "❌ sensitiveLabel button not found — check UserActionsView")
        sensitiveCell.tap()
        Thread.sleep(forTimeInterval: shortDelay)

        // ── Phase 4: Swipe events (PageCarousel) ──
        print("🟦 👆 Phase 4: Swipe gestures in PageCarousel…")
        let pageControllerCell = app.staticTexts["Page Controller"].firstMatch
        XCTAssertTrue(pageControllerCell.waitForExistence(timeout: elementTimeout),
                      "❌ 'Page Controller' cell not found — check UserActionsView")
        pageControllerCell.tap()
        Thread.sleep(forTimeInterval: shortDelay)

        // SwiftUI's TabView(.page) may expose as scrollView OR otherElement depending on iOS version.
        // Use the universal descendants query to find the element regardless of type.
        let pageCarousel = app.descendants(matching: .any)
            .matching(identifier: "pageControllerScrollView").firstMatch
        XCTAssertTrue(pageCarousel.waitForExistence(timeout: elementTimeout),
                      "❌ pageControllerScrollView not found — check PageCarouselView.accessibilityIdentifier")
        slowSwipe(on: pageCarousel, direction: .left)
        Thread.sleep(forTimeInterval: shortDelay)
        slowSwipe(on: pageCarousel, direction: .right)
        Thread.sleep(forTimeInterval: shortDelay)
        navigateBack()

        // ── Phase 5: Flush + schema validation ──
        print("🟦 \n⏳ Phase 5: Flushing events to backend…")
        flushAndValidate()

        // ── Phase 6: Verify events in backend data ──
        print("🟦 \n🔎 Phase 6: Verifying events in backend data…")
        guard let data = readValidationData() else {
            handleMissingValidationData()
            return
        }

        printInteractionEventsSummary(data)

        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "scroll", direction: "down"),
                      "❌ Missing scroll event with direction 'down'")
        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "scroll", direction: "up"),
                      "❌ Missing scroll event with direction 'up'")
        print("🟦 ✅ Scroll events (down + up) verified")

        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "swipe", direction: "left"),
                      "❌ Missing swipe event with direction 'left'")
        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "swipe", direction: "right"),
                      "❌ Missing swipe event with direction 'right'")
        print("🟦 ✅ Swipe events (left + right) verified")

        // In SwiftUI, List button taps are delivered to the CellHostingView wrapper —
        // accessibilityIdentifier set via .accessibilityIdentifier() on the SwiftUI Button
        // does not propagate to the underlying hit-tested UIView, so resolveTargetName
        // cannot map "loginButton" → "Login Button" the way UIKit's UIButton can.
        // We assert at least one click event was captured to verify tap instrumentation works.
        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "click"),
                      "❌ No click events found — tap instrumentation may not be working in SwiftUI")
        print("🟦 ✅ Click events captured (tap instrumentation verified)")

        // shouldSendText: the suppressed text must not appear in any click event's inner_text.
        let suppressedText = "Sensitive Label (text suppressed)"
        XCTAssertFalse(hasInteractionEventWithInnerTextValue(in: data,
                                                             eventName: "click",
                                                             innerText: suppressedText),
                       "❌ shouldSendText failed: '\(suppressedText)' found in target_element_inner_text")
        print("🟦 ✅ shouldSendText (sensitiveLabel suppression) verified")

        print("🟦 \n🎉 All user interaction events verified end-to-end!")
        print("🟦 ========================================\n")
    }

    // MARK: - Gesture helpers

    private enum SwipeDir { case left, right, up, down }

    private func slowSwipe(on element: XCUIElement, direction: SwipeDir) {
        let frame = element.frame
        let cx = frame.midX
        let cy = frame.midY
        let hOffset: CGFloat = frame.width  * 0.35
        let vOffset: CGFloat = frame.height * 0.35

        let (startX, startY, endX, endY): (CGFloat, CGFloat, CGFloat, CGFloat)
        switch direction {
        case .left:  (startX, startY, endX, endY) = (cx + hOffset, cy, cx - hOffset, cy)
        case .right: (startX, startY, endX, endY) = (cx - hOffset, cy, cx + hOffset, cy)
        case .up:    (startX, startY, endX, endY) = (cx, cy + vOffset, cx, cy - vOffset)
        case .down:  (startX, startY, endX, endY) = (cx, cy - vOffset, cx, cy + vOffset)
        }

        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: startX, dy: startY))
        let end = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: endX, dy: endY))

        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: .slow, thenHoldForDuration: 0)
    }

    // MARK: - Navigation helpers

    private func navigateToUserActions() {
        print("🟦 🧭 Navigating to User Actions…")
        let cell = app.staticTexts["User actions"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: elementTimeout),
                      "❌ 'User actions' cell not found on main menu")
        cell.tap()
        Thread.sleep(forTimeInterval: shortDelay)
        XCTAssertTrue(app.staticTexts["Page Controller"].waitForExistence(timeout: elementTimeout),
                      "❌ 'Page Controller' not found — may not be on User Actions screen")
        print("🟦 ✅ On User Actions screen")
    }

    private func navigateBack() {
        print("🟦 🧭 Navigating back…")
        tapBackButton(failureMessage: "❌ Back button not found")
    }

    private func navigateBackToMainMenu() {
        print("🟦 🧭 Navigating to main menu…")
        tapBackButton(failureMessage: "❌ Back button not found — cannot return to main menu")
        let schemaCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        XCTAssertTrue(schemaCell.waitForExistence(timeout: elementTimeout),
                      "❌ Did not return to main menu")
        print("🟦 ✅ Back on main menu")
    }

    private func tapBackButton(failureMessage: String) {
        let backButton = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: elementTimeout), failureMessage)
        backButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)
    }

    private func navigateToSchemaValidation() {
        print("🟦 🧭 Navigating to Schema validation…")
        let schemaCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        XCTAssertTrue(schemaCell.waitForExistence(timeout: elementTimeout),
                      "❌ 'Schema validation' cell not found")
        schemaCell.tap()
        Thread.sleep(forTimeInterval: shortDelay)
        XCTAssertTrue(app.buttons["Validate Schema"].waitForExistence(timeout: elementTimeout),
                      "❌ 'Validate Schema' button not found")
        print("🟦 ✅ On Schema validation screen")
    }

    // MARK: - Flush & validate helpers

    private func flushAndValidate() {
        print("🟦 ⏳ Waiting \(sdkFlushDelay)s for SDK to flush events to backend…")
        Thread.sleep(forTimeInterval: sdkFlushDelay)
        navigateBackToMainMenu()
        navigateToSchemaValidation()
        validateSchemaWithRetry()
    }

    private func triggerValidation() {
        print("🟦 🔍 Triggering schema validation…")
        let validateButton = app.buttons["Validate Schema"]
        XCTAssertTrue(validateButton.waitForExistence(timeout: elementTimeout),
                      "❌ 'Validate Schema' button not found")
        XCTAssertTrue(validateButton.isEnabled, "❌ 'Validate Schema' button is disabled")
        validateButton.tap()
        Thread.sleep(forTimeInterval: networkDelay)
        print("🟦 ✅ Validation request sent")
    }

    private func validateSchemaWithRetry(file: StaticString = #file, line: UInt = #line) {
        let maxAttempts = isCI ? 3 : 2
        for attempt in 1...maxAttempts {
            print("🟦 🔁 Schema validation attempt \(attempt)/\(maxAttempts)")
            triggerValidation()
            if verifySchemaValidationPassed() { return }

            let visibleLabels = app.staticTexts.allElementsBoundByIndex.map { $0.label }
            let combined = visibleLabels.joined(separator: " | ")
            let isRetryable = combined.contains("Network error:")
                || combined.contains("Internet connection appears to be offline")
                || combined.contains("timed out")
                || combined.contains("could not connect")

            if attempt < maxAttempts && isRetryable {
                print("🟨 Schema validation hit transient network issue, retrying…")
                Thread.sleep(forTimeInterval: networkDelay)
                continue
            }

            XCTFail(
                "Schema validation failed after \(attempt) attempt(s). Visible labels: [\(visibleLabels.joined(separator: ", "))]",
                file: file, line: line
            )
            return
        }
    }

    private func verifySchemaValidationPassed() -> Bool {
        print("🟦 🔍 Checking schema validation result…")
        let successLabel = app.staticTexts["All logs are valid! ✅"]
        if successLabel.waitForExistence(timeout: networkDelay) {
            print("🟦 ✅ Schema validation passed!")
            return true
        }
        return false
    }

    // MARK: - Temp-file I/O

    private func clearValidationData() {
        try? FileManager.default.removeItem(atPath: "/tmp/coralogix_validation_response.json")
    }

    private func readValidationData() -> [[String: Any]]? {
        let path = "/tmp/coralogix_validation_response.json"
        guard FileManager.default.fileExists(atPath: path),
              let jsonData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("🟨  Validation file not found at \(path)")
            return nil
        }

        if let wrapped = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
           wrapped.first?["logs"] != nil {
            var all: [[String: Any]] = []
            for item in wrapped {
                if let logs = item["logs"] as? [[String: Any]] { all.append(contentsOf: logs) }
            }
            print("🟦 📊 Read \(all.count) log entries (unwrapped from \(wrapped.count) validation objects)")
            return all
        }

        if let direct = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            print("🟦 📊 Read \(direct.count) log entries (direct array)")
            return direct
        }

        let preview = String(data: jsonData.prefix(200), encoding: .utf8) ?? "<unreadable>"
        XCTFail("Failed to parse validation response JSON. Preview: \(preview)")
        return nil
    }

    private func handleMissingValidationData(file: StaticString = #file, line: UInt = #line) {
        if isCI {
            XCTFail("Validation data file required in CI mode", file: file, line: line)
        } else {
            print("🟦 ℹ️  Local mode — skipping temp-file verification (UI-only pass)")
        }
    }

    // MARK: - Event-verification predicates

    private func extractInteractionContext(from logEntry: [String: Any]) -> [String: Any]? {
        if let text = logEntry["text"] as? [String: Any],
           let cxRum = text["cx_rum"] as? [String: Any],
           let ctx = cxRum["interaction_context"] as? [String: Any] {
            return ctx
        }
        if let ctx = logEntry["interaction_context"] as? [String: Any] { return ctx }
        return nil
    }

    private func hasInteractionEvent(
        in logs: [[String: Any]],
        eventName: String,
        direction: String? = nil,
        targetElement: String? = nil,
        elementId: String? = nil
    ) -> Bool {
        for entry in logs {
            guard let ctx = extractInteractionContext(from: entry) else { continue }
            guard let name = ctx["event_name"] as? String, name == eventName else { continue }
            if let dir = direction {
                guard let d = ctx["scroll_direction"] as? String, d == dir else { continue }
            }
            if let te = targetElement {
                guard let t = ctx["target_element"] as? String, t == te else { continue }
            }
            if let eid = elementId {
                guard let e = ctx["element_id"] as? String, e == eid else { continue }
            }
            return true
        }
        return false
    }

    private func hasInteractionEventWithInnerTextValue(
        in logs: [[String: Any]],
        eventName: String,
        innerText: String
    ) -> Bool {
        for entry in logs {
            guard let ctx = extractInteractionContext(from: entry) else { continue }
            guard let name = ctx["event_name"] as? String, name == eventName else { continue }
            guard let text = ctx["target_element_inner_text"] as? String else { continue }
            if text.contains(innerText) { return true }
        }
        return false
    }

    // MARK: - Debugging helpers

    private func printInteractionEventsSummary(_ logs: [[String: Any]]) {
        let interactionLogs = logs.compactMap { entry -> ([String: Any], [String: Any])? in
            guard let ctx = extractInteractionContext(from: entry) else { return nil }
            return (entry, ctx)
        }
        print("🟦 \n📋 Interaction events found in validation data: \(interactionLogs.count)")
        for (i, (_, ctx)) in interactionLogs.enumerated() {
            let name      = ctx["event_name"] as? String ?? "?"
            let dir       = ctx["scroll_direction"] as? String ?? "-"
            let target    = ctx["target_element"] as? String ?? "?"
            let eid       = ctx["element_id"] as? String ?? "-"
            let innerText = ctx["target_element_inner_text"] as? String
            print("🟦    [\(i)] name=\(name) dir=\(dir) target=\(target) eid=\(eid) text=\(innerText ?? "-")")
        }
    }
}

// MARK: - How to Run

/*

 ## Xcode (local development):
 1. Open Example/DemoApp.xcworkspace
 2. Select "DemoAppSwiftUI" scheme
 3. Click ◇ next to testAllUserInteractionEvents_combinedSchemaValidation
 4. Requires a running validation proxy (Envs.PROXY_URL)

 ## Command line (CI):
 ```bash
 cd Example
 xcodebuild test \
   -workspace DemoApp.xcworkspace \
   -scheme DemoAppSwiftUI \
   -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
   -only-testing:DemoAppSwiftUIUITests/UserInteractionUITests/testAllUserInteractionEvents_combinedSchemaValidation
 ```

 ## Scenarios covered:
 | Phase | Events verified                                      |
 |-------|------------------------------------------------------|
 | 1     | scroll/down, scroll/up (List swipe)                  |
 | 2     | click — any click event captured (tap instrumentation works) |
 | 3     | click — target_element_inner_text absent (shouldSendText)   |
 | 4     | swipe/left, swipe/right (PageCarousel TabView)       |

*/
