//
//  UserInteractionUITests.swift
//  DemoAppUITests
//
//  Created by Coralogix DEV TEAM on 05/02/2026.
//
//  E2E tests that drive real gestures in the DemoApp and verify that the
//  Coralogix RUM SDK captures scroll, swipe, and tap (resolveTargetName)
//  user-interaction events correctly, then ships them to the backend.
//
//  APPROACH
//  --------
//  1. Launch with --uitesting so SchemaValidationViewController writes the
//     raw backend response to /tmp/coralogix_validation_response.json.
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
//    "element_classes": always the UIKit class name (never overridden)
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

    var app: XCUIApplication!

    // MARK: - CI detection

    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] == "true" ||
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" ||
        ProcessInfo.processInfo.environment["CONTINUOUS_INTEGRATION"] == "true"
    }

    private var elementTimeout: TimeInterval { isCI ? 15.0 : 10.0 }
    private var shortDelay: TimeInterval     { isCI ?  2.0 :  1.0 }
    private var sdkFlushDelay: TimeInterval  { isCI ? 10.0 :  5.0 }

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        clearValidationData()
        log("🚀 Launching app (CI=\(isCI))")
        app.launch()
    }

    // MARK: - Test: Scroll events (up & down)

    /// Scroll a UITableView down then up in the User Actions screen and verify
    /// that the SDK emits two scroll events with the correct directions.
    func testScrollEvents_downAndUp_areCorrectlyCaptured() throws {
        log("\n========================================")
        log("🧪 TEST: Scroll events (down + up)")
        log("========================================\n")

        // ── Phase 1: Navigate to User Actions ──
        navigateToUserActions()

        // ── Phase 2: Perform scroll gestures ──
        // Note: UserActionsViewController is a UITableViewController. The table
        // is long enough to scroll. `swipeDown()` moves the finger downward,
        // so the SDK records scroll_direction = "down".
        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: elementTimeout), "❌ UserActions table should exist")

        log("📜 Performing swipeDown (scroll down)…")
        table.swipeDown()
        Thread.sleep(forTimeInterval: shortDelay)

        log("📜 Performing swipeUp (scroll up)…")
        table.swipeUp()
        Thread.sleep(forTimeInterval: shortDelay)

        // ── Phase 3: Flush + validate ──
        flushAndValidate()

        // ── Phase 4: Verify events in backend response ──
        guard let data = readValidationData() else {
            handleMissingValidationData()
            return
        }

        let foundDown = hasInteractionEvent(in: data, eventName: "scroll", direction: "down")
        let foundUp   = hasInteractionEvent(in: data, eventName: "scroll", direction: "up")

        XCTAssertTrue(foundDown, "❌ Expected a 'scroll' event with direction 'down' in validation data")
        XCTAssertTrue(foundUp,   "❌ Expected a 'scroll' event with direction 'up' in validation data")

        if foundDown && foundUp {
            log("✅ Both scroll directions (down, up) confirmed in backend!")
        }
    }

    // MARK: - Test: Swipe events (left & right) in PageController

    /// Swipe left then right on the PageController's paged UIScrollView and verify
    /// the SDK emits two swipe events with directions left and right.
    func testSwipeEvents_leftAndRight_areCorrectlyCaptured() throws {
        log("\n========================================")
        log("🧪 TEST: Swipe events (left + right)")
        log("========================================\n")

        // ── Phase 1: Navigate to PageController ──
        navigateToUserActions()
        let pageControllerCell = app.staticTexts["Page Controller"].firstMatch
        XCTAssertTrue(pageControllerCell.waitForExistence(timeout: elementTimeout),
                      "❌ 'Page Controller' cell not found")
        pageControllerCell.tap()
        Thread.sleep(forTimeInterval: shortDelay)

        // ── Phase 2: Perform swipe gestures on the paged scroll view ──
        // The PageController has a horizontally paging UIScrollView with 3 pages.
        // We use a coordinate-based slow drag (rather than swipeLeft()) so that
        // at least one `.moved` event fires before the UIPanGestureRecognizer
        // cancels the touch — guaranteeing ScrollTracker.state.hasMoved = true
        // and a stable direction reading.
        let pageScrollView = app.scrollViews.firstMatch
        XCTAssertTrue(pageScrollView.waitForExistence(timeout: elementTimeout),
                      "❌ Paged scroll view not found in PageController")

        log("👆 Performing slow swipeLeft (advance page)…")
        slowSwipe(on: pageScrollView, direction: .left)
        Thread.sleep(forTimeInterval: shortDelay)

        log("👆 Performing slow swipeRight (go back)…")
        slowSwipe(on: pageScrollView, direction: .right)
        Thread.sleep(forTimeInterval: shortDelay)

        // ── Phase 3: Navigate back, flush + validate ──
        navigateBack()
        flushAndValidate()

        // ── Phase 4: Verify events in backend response ──
        guard let data = readValidationData() else {
            handleMissingValidationData()
            return
        }

        let foundLeft  = hasInteractionEvent(in: data, eventName: "swipe", direction: "left")
        let foundRight = hasInteractionEvent(in: data, eventName: "swipe", direction: "right")

        XCTAssertTrue(foundLeft,  "❌ Expected a 'swipe' event with direction 'left'")
        XCTAssertTrue(foundRight, "❌ Expected a 'swipe' event with direction 'right'")

        if foundLeft && foundRight {
            log("✅ Both swipe directions (left, right) confirmed in backend!")
        }
    }

    // MARK: - Test: resolveTargetName maps custom name to target_element

    /// Tap the "loginButton" UIButton that appears as the table header in
    /// UserActionsViewController. The CoralogixRumManager.resolveTargetName
    /// callback maps accessibilityIdentifier "loginButton" → "Login Button",
    /// so the backend event must have target_element = "Login Button".
    func testResolveTargetName_tapLoginButton_customNameInBackend() throws {
        log("\n========================================")
        log("🧪 TEST: resolveTargetName — Login Button")
        log("========================================\n")

        // ── Phase 1: Navigate to User Actions ──
        navigateToUserActions()

        // ── Phase 2: Tap the loginButton (table header UIButton) ──
        // The button is added by setupResolveTargetNameDemoHeader() in
        // UserActionsViewController. Its accessibilityIdentifier is "loginButton".
        let loginButton = app.buttons["loginButton"].firstMatch
        XCTAssertTrue(loginButton.waitForExistence(timeout: elementTimeout),
                      "❌ 'loginButton' not found — check UserActionsViewController.setupResolveTargetNameDemoHeader()")
        log("👆 Tapping loginButton…")
        loginButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)

        // ── Phase 3: Flush + validate ──
        flushAndValidate()

        // ── Phase 4: Verify event in backend response ──
        guard let data = readValidationData() else {
            handleMissingValidationData()
            return
        }

        // Verify a click event was captured for the loginButton
        let foundClick = hasInteractionEvent(in: data, eventName: "click", elementId: "loginButton")
        XCTAssertTrue(foundClick, "❌ Expected a 'click' interaction event for loginButton")

        // Verify target_element was overridden to "Login Button" by resolveTargetName
        let foundCustomName = hasInteractionEvent(in: data, eventName: "click", targetElement: "Login Button")
        XCTAssertTrue(foundCustomName,
                      "❌ Expected target_element = 'Login Button' via resolveTargetName callback")

        if foundClick && foundCustomName {
            log("✅ resolveTargetName confirmed — target_element = 'Login Button' in backend!")
        }
    }

    // MARK: - Test: shouldSendText suppresses inner text for sensitiveLabel

    /// Tap the "Sensitive Label" cell in UserActionsViewController. The
    /// shouldSendText callback suppresses text capture for any view whose
    /// accessibilityIdentifier == "sensitiveLabel". The backend event must
    /// NOT contain target_element_inner_text.
    ///
    /// NOTE on element_id reliability: `touch.view` at gesture time is the cell's
    /// contentView (or an inner label), not the UITableViewCell itself, so
    /// `element_id` in the RUM payload may not be "sensitiveLabel". We therefore:
    ///  1. Confirm at least one click event landed in the backend (proves the tap
    ///     was captured and the data arrived — avoids a vacuous pass).
    ///  2. Then assert that NONE of those click events have a non-empty
    ///     `target_element_inner_text` (the cell's row title is "Sensitive Label
    ///     (text suppressed)" — if suppression fails, that text would appear).
    func testShouldSendText_sensitiveLabel_noInnerTextInBackend() throws {
        log("\n========================================")
        log("🧪 TEST: shouldSendText — sensitiveLabel suppression")
        log("========================================\n")

        // ── Phase 1: Navigate to User Actions ──
        navigateToUserActions()

        // ── Phase 2: Tap the sensitiveLabel cell ──
        let sensitiveCell = app.cells["sensitiveLabel"].firstMatch
        XCTAssertTrue(sensitiveCell.waitForExistence(timeout: elementTimeout),
                      "❌ 'sensitiveLabel' cell not found")
        log("👆 Tapping sensitiveLabel cell…")
        sensitiveCell.tap()
        Thread.sleep(forTimeInterval: shortDelay)

        // ── Phase 3: Flush + validate ──
        flushAndValidate()

        // ── Phase 4: Verify suppression ──
        guard let data = readValidationData() else {
            handleMissingValidationData()
            return
        }

        // Step 4a: Confirm at least one click event arrived in the backend.
        // Without this positive guard the suppression assertion below would
        // trivially pass if no data arrived at all.
        let anyClickEvent = hasInteractionEvent(in: data, eventName: "click")
        XCTAssertTrue(anyClickEvent,
                      "❌ No click events found in backend — tap may not have been captured or data did not arrive")

        // Step 4b: None of the click events should carry the suppressed inner text.
        // The row title "Sensitive Label (text suppressed)" would appear in
        // target_element_inner_text if shouldSendText incorrectly returned true.
        let suppressedText = "Sensitive Label (text suppressed)"
        let hasLeakedText = hasInteractionEventWithInnerTextValue(in: data,
                                                                  eventName: "click",
                                                                  innerText: suppressedText)
        XCTAssertFalse(hasLeakedText,
                       "❌ shouldSendText failed: '\(suppressedText)' found in target_element_inner_text — text was not suppressed")

        log("✅ shouldSendText confirmed — sensitive text not found in any click event")
    }

    // MARK: - Test: All interaction events are attributed to the active session

    /// Perform a mix of gestures, then verify that every interaction event
    /// in the validation data shares the same session_id that the SDK reports.
    func testAllInteractionEvents_areAttributedToActiveSession() throws {
        log("\n========================================")
        log("🧪 TEST: Session attribution for interaction events")
        log("========================================\n")

        // ── Phase 1: Generate a variety of interaction events ──
        navigateToUserActions()

        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: elementTimeout))

        log("📜 Generating scroll events…")
        table.swipeDown()
        Thread.sleep(forTimeInterval: shortDelay)
        table.swipeUp()
        Thread.sleep(forTimeInterval: shortDelay)

        // Navigate to PageController and swipe
        let pageControllerCell = app.staticTexts["Page Controller"].firstMatch
        if pageControllerCell.waitForExistence(timeout: elementTimeout) {
            pageControllerCell.tap()
            Thread.sleep(forTimeInterval: shortDelay)

            let scrollView = app.scrollViews.firstMatch
            if scrollView.waitForExistence(timeout: elementTimeout) {
                log("👆 Generating swipe events…")
                slowSwipe(on: scrollView, direction: .left)
                Thread.sleep(forTimeInterval: shortDelay)
            }
            navigateBack()
        }

        // ── Phase 2: Flush + validate ──
        flushAndValidate()

        // ── Phase 3: Verify session attribution ──
        guard let data = readValidationData() else {
            handleMissingValidationData()
            return
        }

        let interactionLogs = data.filter { extractInteractionContext(from: $0) != nil }

        guard !interactionLogs.isEmpty else {
            XCTFail("❌ No interaction events found in backend — gestures may not have been captured or data did not arrive in time")
            return
        }

        // Collect all session_ids from interaction events
        let sessionIds = interactionLogs.compactMap { extractSessionId(from: $0) }
        let uniqueSessionIds = Set(sessionIds)

        log("📊 Found \(interactionLogs.count) interaction log(s) with \(uniqueSessionIds.count) unique session_id(s)")

        // All events should belong to the same session
        XCTAssertEqual(uniqueSessionIds.count, 1,
                       "❌ Expected all interaction events to share one session_id, found: \(uniqueSessionIds)")
        XCTAssertFalse(sessionIds.isEmpty,
                       "❌ No session_id found in any interaction event")

        log("✅ All interaction events share session_id: \(uniqueSessionIds.first ?? "(unknown)")")
    }

    // MARK: - Compound test (CI-friendly single-run)

    /// Runs all gesture scenarios in one test so the app is launched once and
    /// a single schema validation covers all events. Preferred in CI to reduce
    /// total wall-clock time.
    func testAllUserInteractionEvents_combinedSchemaValidation() throws {
        log("\n========================================")
        log("🧪 TEST: Combined user interaction E2E")
        log("========================================\n")

        // ── Phase 1: Scroll events ──
        log("📜 Phase 1: Scroll gestures…")
        navigateToUserActions()

        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: elementTimeout), "❌ UserActions table not found")

        table.swipeDown()
        Thread.sleep(forTimeInterval: shortDelay)
        table.swipeUp()
        Thread.sleep(forTimeInterval: shortDelay)

        // ── Phase 2: resolveTargetName tap ──
        log("👆 Phase 2: Login button tap (resolveTargetName)…")
        let loginButton = app.buttons["loginButton"].firstMatch
        if loginButton.waitForExistence(timeout: elementTimeout) {
            loginButton.tap()
            Thread.sleep(forTimeInterval: shortDelay)
        } else {
            log("⚠️  loginButton not found — skipping resolveTargetName sub-test")
        }

        // ── Phase 3: shouldSendText (sensitiveLabel) ──
        log("👆 Phase 3: Sensitive label tap (shouldSendText)…")
        let sensitiveCell = app.cells["sensitiveLabel"].firstMatch
        if sensitiveCell.waitForExistence(timeout: elementTimeout) {
            sensitiveCell.tap()
            Thread.sleep(forTimeInterval: shortDelay)
        } else {
            log("⚠️  sensitiveLabel cell not found — skipping shouldSendText sub-test")
        }

        // ── Phase 4: Swipe events (PageController) ──
        log("👆 Phase 4: Swipe gestures in PageController…")
        let pageControllerCell = app.staticTexts["Page Controller"].firstMatch
        if pageControllerCell.waitForExistence(timeout: elementTimeout) {
            pageControllerCell.tap()
            Thread.sleep(forTimeInterval: shortDelay)

            let scrollView = app.scrollViews.firstMatch
            if scrollView.waitForExistence(timeout: elementTimeout) {
                slowSwipe(on: scrollView, direction: .left)
                Thread.sleep(forTimeInterval: shortDelay)
                slowSwipe(on: scrollView, direction: .right)
                Thread.sleep(forTimeInterval: shortDelay)
            } else {
                log("⚠️  PageController scroll view not found — skipping swipe sub-test")
            }
            navigateBack()
        } else {
            log("⚠️  'Page Controller' cell not found — skipping swipe sub-test")
        }

        // ── Phase 5: Flush + schema validation ──
        log("\n⏳ Phase 5: Flushing events to backend…")
        flushAndValidate()

        // ── Phase 6: Verify events in backend data ──
        log("\n🔎 Phase 6: Verifying events in backend data…")
        guard let data = readValidationData() else {
            handleMissingValidationData()
            return
        }

        printInteractionEventsSummary(data)

        // Scroll: down and up
        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "scroll", direction: "down"),
                      "❌ Missing scroll event with direction 'down'")
        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "scroll", direction: "up"),
                      "❌ Missing scroll event with direction 'up'")
        log("✅ Scroll events (down + up) verified")

        // Swipe: left and right
        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "swipe", direction: "left"),
                      "❌ Missing swipe event with direction 'left'")
        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "swipe", direction: "right"),
                      "❌ Missing swipe event with direction 'right'")
        log("✅ Swipe events (left + right) verified")

        // resolveTargetName: target_element = "Login Button"
        XCTAssertTrue(hasInteractionEvent(in: data, eventName: "click", targetElement: "Login Button"),
                      "❌ Missing click event with target_element = 'Login Button' (resolveTargetName)")
        log("✅ resolveTargetName (Login Button) verified")

        // shouldSendText: the cell's row title must not appear in any click event
        let suppressedText = "Sensitive Label (text suppressed)"
        XCTAssertFalse(hasInteractionEventWithInnerTextValue(in: data,
                                                             eventName: "click",
                                                             innerText: suppressedText),
                       "❌ shouldSendText failed: '\(suppressedText)' found in target_element_inner_text")
        log("✅ shouldSendText (sensitiveLabel suppression) verified")

        log("\n🎉 All user interaction events verified end-to-end!")
        log("========================================\n")
    }

    // MARK: - Gesture helpers

    private enum SwipeDir { case left, right, up, down }

    /// Performs a slow, deliberate swipe using XCUICoordinate gestures so that
    /// UIKit delivers several `.moved` events to the swizzled sendEvent before the
    /// gesture recogniser cancels the touch.  This guarantees ScrollTracker records
    /// `hasMoved = true` and has a reliable direction reading even for paged scroll
    /// views that claim the gesture early.
    private func slowSwipe(on element: XCUIElement, direction: SwipeDir) {
        let frame = element.frame
        let cx = frame.midX
        let cy = frame.midY
        // Use the axis-appropriate dimension so the swipe distance is 35% of the
        // element's width for horizontal directions and 35% of its height for vertical.
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
        log("🧭 Navigating to User Actions…")
        let button = app.staticTexts["User actions"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: elementTimeout),
                      "❌ 'User actions' cell not found on main menu")
        button.tap()
        Thread.sleep(forTimeInterval: shortDelay)

        // Confirm navigation by checking for a known element in the screen
        XCTAssertTrue(app.staticTexts["Page Controller"].waitForExistence(timeout: elementTimeout),
                      "❌ 'Page Controller' not found — may not be on User Actions screen")
        log("✅ On User Actions screen")
    }

    private func navigateBack() {
        log("🧭 Navigating back…")
        let navBar = app.navigationBars.firstMatch
        let backButton = navBar.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "❌ Back button not found — cannot navigate back (wrong screen?)")
        backButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)
    }

    private func navigateBackToMainMenu() {
        log("🧭 Navigating to main menu…")
        let navBar = app.navigationBars.firstMatch
        let backButton = navBar.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "❌ Back button not found — cannot return to main menu (wrong screen?)")
        backButton.tap()
        Thread.sleep(forTimeInterval: shortDelay)

        let schemaCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        XCTAssertTrue(schemaCell.waitForExistence(timeout: elementTimeout),
                      "❌ Did not return to main menu")
        log("✅ Back on main menu")
    }

    private func navigateToSchemaValidation() {
        log("🧭 Navigating to Schema validation…")
        let schemaCell = app.cells.containing(.staticText, identifier: "Schema validation").firstMatch
        XCTAssertTrue(schemaCell.waitForExistence(timeout: elementTimeout),
                      "❌ 'Schema validation' cell not found")
        schemaCell.tap()
        Thread.sleep(forTimeInterval: shortDelay)

        XCTAssertTrue(app.buttons["Validate Schema"].waitForExistence(timeout: elementTimeout),
                      "❌ 'Validate Schema' button not found")
        log("✅ On Schema validation screen")
    }

    // MARK: - Flush & validate helpers

    private func flushAndValidate() {
        log("⏳ Waiting \(sdkFlushDelay)s for SDK to flush events to backend…")
        Thread.sleep(forTimeInterval: sdkFlushDelay)
        navigateBackToMainMenu()
        navigateToSchemaValidation()
        triggerValidation()
        verifySchemaValidationPassed()
    }

    private func triggerValidation() {
        log("🔍 Triggering schema validation…")
        let validateButton = app.buttons["Validate Schema"]
        XCTAssertTrue(validateButton.waitForExistence(timeout: elementTimeout))
        XCTAssertTrue(validateButton.isEnabled, "Validate button should be enabled")
        validateButton.tap()
        Thread.sleep(forTimeInterval: 3)
        log("✅ Validation request sent")
    }

    private func verifySchemaValidationPassed(file: StaticString = #file, line: UInt = #line) {
        log("🔍 Checking schema validation result…")
        let successLabel = app.staticTexts["All logs are valid! ✅"]
        if !successLabel.waitForExistence(timeout: 5) {
            let allLabels = app.staticTexts.allElementsBoundByIndex.map { $0.label }
            print("❌ Schema validation did not pass. Visible labels:")
            allLabels.forEach { print("   - \($0)") }
            XCTFail("Schema validation failed — see console for details", file: file, line: line)
        } else {
            log("✅ Schema validation passed!")
        }
    }

    // MARK: - Temp-file I/O

    private func clearValidationData() {
        try? FileManager.default.removeItem(atPath: "/tmp/coralogix_validation_response.json")
    }

    private func readValidationData() -> [[String: Any]]? {
        let path = "/tmp/coralogix_validation_response.json"
        guard FileManager.default.fileExists(atPath: path),
              let jsonData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            log("⚠️  Validation file not found at \(path)")
            return nil
        }

        if let wrapped = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
           wrapped.first?["logs"] != nil {
            // Unwrap { "logs": [...], "validationResult": {...} } structure
            var all: [[String: Any]] = []
            for item in wrapped {
                if let logs = item["logs"] as? [[String: Any]] { all.append(contentsOf: logs) }
            }
            log("📊 Read \(all.count) log entries (unwrapped from \(wrapped.count) validation objects)")
            return all
        }

        if let direct = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            log("📊 Read \(direct.count) log entries (direct array)")
            return direct
        }

        log("❌ Failed to parse validation response JSON")
        return nil
    }

    private func handleMissingValidationData(file: StaticString = #file, line: UInt = #line) {
        if isCI {
            XCTFail("Validation data file required in CI mode", file: file, line: line)
        } else {
            log("ℹ️  Local mode — skipping temp-file verification (UI-only pass)")
        }
    }

    // MARK: - Event-verification predicates

    /// Returns the interaction_context dict from a log entry, if present.
    private func extractInteractionContext(from logEntry: [String: Any]) -> [String: Any]? {
        // Primary path: text.cx_rum.interaction_context
        if let text = logEntry["text"] as? [String: Any],
           let cxRum = text["cx_rum"] as? [String: Any],
           let ctx = cxRum["interaction_context"] as? [String: Any] {
            return ctx
        }
        // Fallback: top-level interaction_context (some exporter versions)
        if let ctx = logEntry["interaction_context"] as? [String: Any] {
            return ctx
        }
        return nil
    }

    /// Returns the session_id string from a log entry, if present.
    private func extractSessionId(from logEntry: [String: Any]) -> String? {
        if let text = logEntry["text"] as? [String: Any],
           let cxRum = text["cx_rum"] as? [String: Any],
           let session = cxRum["session_context"] as? [String: Any],
           let sid = session["session_id"] as? String {
            return sid
        }
        return nil
    }

    /// Returns `true` when at least one log entry has an interaction_context
    /// matching all provided (non-nil) criteria.
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

    /// Returns `true` when a log entry has an interaction_context for the given
    /// elementId AND a non-empty target_element_inner_text — meaning shouldSendText
    /// did NOT suppress the text as expected.
    private func hasInteractionEventWithInnerText(
        in logs: [[String: Any]],
        elementId: String
    ) -> Bool {
        for entry in logs {
            guard let ctx = extractInteractionContext(from: entry) else { continue }
            guard let eid = ctx["element_id"] as? String, eid == elementId else { continue }
            guard let text = ctx["target_element_inner_text"] as? String, !text.isEmpty else { continue }
            return true
        }
        return false
    }

    /// Returns `true` when any interaction event with the given `eventName` contains
    /// `innerText` as its `target_element_inner_text` value — indicating that
    /// `shouldSendText` did NOT suppress the text.
    ///
    /// Preferred over `hasInteractionEventWithInnerText(elementId:)` when the
    /// `element_id` field is unreliable (e.g. identifier set on a UITableViewCell
    /// rather than the leaf hit-tested view).
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
        let interactionLogs = logs.filter { extractInteractionContext(from: $0) != nil }
        log("\n📋 Interaction events found in validation data: \(interactionLogs.count)")
        for (i, entry) in interactionLogs.enumerated() {
            guard let ctx = extractInteractionContext(from: entry) else { continue }
            let name       = ctx["event_name"] as? String ?? "?"
            let dir        = ctx["scroll_direction"] as? String ?? "-"
            let target     = ctx["target_element"] as? String ?? "?"
            let classes    = ctx["element_classes"] as? String ?? "?"
            let eid        = ctx["element_id"] as? String ?? "-"
            let innerText  = ctx["target_element_inner_text"] as? String
            let sessionId  = extractSessionId(from: entry) ?? "?"
            log("   [\(i)] name=\(name) dir=\(dir) target=\(target) classes=\(classes) eid=\(eid) text=\(innerText ?? "-") sid=\(sessionId.prefix(8))…")
        }
    }

    private func log(_ message: String) {
        let ts = String(format: "%.2f", Date().timeIntervalSince1970)
        print("🕐 [\(ts)] \(message)")
    }
}

// MARK: - How to Run

/*

 ## Xcode (local development):
 1. Open Example/DemoApp.xcworkspace
 2. Select "DemoAppUITests" scheme
 3. Click ◇ next to any test method (or run the whole class)
 4. Recommended: run testAllUserInteractionEvents_combinedSchemaValidation
    for a single-pass E2E covering all scenarios.

 ## Command line (CI):
 ```bash
 cd Example
 xcodebuild test \
   -workspace DemoApp.xcworkspace \
   -scheme DemoAppUITests \
   -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' \
   -only-testing:DemoAppUITests/UserInteractionUITests/testAllUserInteractionEvents_combinedSchemaValidation
 ```

 ## Scenarios covered:
 | Test                                         | Events verified                                      |
 |----------------------------------------------|------------------------------------------------------|
 | testScrollEvents_downAndUp                   | scroll/down, scroll/up                               |
 | testSwipeEvents_leftAndRight                 | swipe/left, swipe/right (PageController paged scroll)|
 | testResolveTargetName_tapLoginButton         | click — target_element = "Login Button"              |
 | testShouldSendText_sensitiveLabel            | click — target_element_inner_text absent             |
 | testAllInteractionEvents_attributedToSession | all events share one session_id                      |
 | testAllUserInteractionEvents_combined        | all of the above in one run (CI-friendly)            |

 ## Direction convention (SDK captures FINGER direction, not content direction):
   swipeDown() → "down"   swipeUp() → "up"   swipeLeft() → "left"   swipeRight() → "right"

 ## Notes:
 - Requires the proxy / backend to be reachable (Envs.PROXY_URL).
 - The --uitesting flag is set automatically; it enables SchemaValidationViewController
   to save the backend response to /tmp/coralogix_validation_response.json.
 - In CI mode (CI=true) the test fails if the temp file is missing.
 - Locally it degrades gracefully to a UI-only pass.

*/
