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

        // Propagate the mock-server port set by the host wrapper script.
        if let mockPort = ProcessInfo.processInfo.environment["CX_MOCK_PORT"] {
            app.launchEnvironment["CX_MOCK_PORT"] = mockPort
        }
        // Note: --leak-harness is set per-test below.
    }

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    // MARK: - 1 fps scenario

    func test_listSlowScroll_1fps() {
        signalScenario("1fps")
        app.launchArguments = ["--leak-harness"]
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
        // at the mock server (1 fps = 1.0 s between captures).
        usleep(5_000_000) // 5 s
    }

    // MARK: - Navigation transition scenario

    /// Rapidly pushes and pops between two sentinel-bearing screens.
    ///
    /// Session-replay frames captured mid-animation show half of ScreenA and
    /// half of ScreenB. The mask walk must use the same coordinate frame as the
    /// rendered bitmap; if it doesn't, ScreenA's sentinels appear unmasked
    /// (magenta pixels leak) in those frames.
    ///
    /// Timing: 30 push+pop cycles at ~900 ms/cycle = ~27 s of transitions.
    /// At 1 fps, ~27 frames captured; ~30% of transitions land mid-animation,
    /// so ~8 mid-transition frames are expected. Any magenta pixel = leak.
    func test_navigationTransition() {
        signalScenario("navigate")
        app.launchArguments = ["--leak-harness-navigate"]
        app.launch()

        let pushButton = app.buttons[NavPushButtonId]
        XCTAssertTrue(pushButton.waitForExistence(timeout: 10),
                      "Navigation leak harness Screen A didn't appear — is --leak-harness-navigate wired in SceneDelegate?")

        for _ in 0..<30 {
            pushButton.tap()

            // Wait for Screen B to enter the hierarchy. `waitForExistence` returns
            // as soon as the element is in the a11y tree — typically within the
            // first 100–200 ms of the push animation (~300 ms total). Tapping pop
            // this early means the pop animation starts while the push animation
            // may still be finishing, maximising the mid-transition capture window.
            let popButton = app.buttons[NavPopButtonId]
            _ = popButton.waitForExistence(timeout: 2)
            popButton.tap()

            // Brief pause so Screen A is settled before the next push.
            usleep(300_000) // 300 ms
        }

        // Let in-flight uploads reach the mock server before the server is killed.
        usleep(5_000_000) // 5 s
    }

    // MARK: - Helpers

    /// Tells the mock server which scenario is about to run so it can
    /// prefix frame filenames (e.g. `1fps_frame_000001.jpg`).
    /// Blocks until the server acknowledges or the port is unavailable.
    private func signalScenario(_ scenario: String) {
        guard let portStr = ProcessInfo.processInfo.environment["CX_MOCK_PORT"],
              let port = Int(portStr),
              let url = URL(string: "http://127.0.0.1:\(port)/scenario?name=\(scenario)")
        else { return }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "POST"
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in sem.signal() }.resume()
        sem.wait()
    }

    private let LeakHarnessTableId = "cx_leak_harness_table"
    private let NavPushButtonId    = "cx_leak_nav_push"
    private let NavPopButtonId     = "cx_leak_nav_pop"
}
