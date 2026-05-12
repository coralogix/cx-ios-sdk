//
//  SessionReplayLeakUITests.swift
//  DemoAppUITests
//
//  BUGV2-6045 native-iOS session-replay leak harness driver.
//  Launches DemoAppSwift with `--leak-harness` so SceneDelegate
//  installs LeakHarnessViewController as root, drives slow scroll on
//  its UITableView, then exits.
//
//  Frame capture + leak detection happen on the host:
//    - Mock proxy server intercepts session-replay uploads via
//      CXExporterOptions.proxyUrl (set in CoralogixRumManager from
//      the CX_MOCK_PORT env var, also propagated here via
//      XCUIApplication.launchEnvironment).
//    - Pixel scanner counts magenta sentinel pixels per frame.
//
//  The wrapper script tool/run_leak_harness.sh handles all of
//  the above and reports pass/fail via exit code.
//

import XCTest

final class SessionReplayLeakUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        app = XCUIApplication()
        // Tell SceneDelegate / AppDelegate to enter harness mode.
        app.launchArguments.append("--leak-harness")

        // Propagate the mock-server port set by the host wrapper script.
        // Read from this test process's env (xcodebuild forwards env to
        // the test runner) and pass it into the launched app via
        // launchEnvironment.
        if let mockPort = ProcessInfo.processInfo.environment["CX_MOCK_PORT"] {
            app.launchEnvironment["CX_MOCK_PORT"] = mockPort
        }
    }

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    func test_listSlowScroll_capturesFrames() {
        app.launch()

        let table = app.tables[LeakHarnessTableId]
        XCTAssertTrue(table.waitForExistence(timeout: 10),
                      "Leak-harness table didn't appear — DemoAppSwift may not have entered --leak-harness mode")

        // Slow controlled scrolling for the LIST scenario. Many short
        // swipes with short pauses, mirroring the Flutter harness's
        // timedDrag pattern (~400 px/s).
        for _ in 0..<25 {
            table.swipeUp(velocity: .slow)
            usleep(150_000) // 150 ms between swipes
        }

        // Wait a few capture intervals for in-flight uploads to land
        // at the mock server. captureTimeInterval is 1.0 s in the
        // harness's AppDelegate-side SessionReplay init.
        usleep(5_000_000) // 5 s
    }

    private let LeakHarnessTableId = "cx_leak_harness_table"
}
