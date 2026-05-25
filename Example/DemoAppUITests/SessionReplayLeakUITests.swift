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
        // Note: --leak-harness (and optional --leak-harness-60fps) are set
        // per-test below so each test controls its own frame-rate config.
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
        // at the mock server. captureTimeInterval is 1.0 s in 1fps mode.
        usleep(5_000_000) // 5 s
    }

    // MARK: - 60 fps scenario

    func test_listSlowScroll_60fps() {
        signalScenario("60fps")
        app.launchArguments = ["--leak-harness", "--leak-harness-60fps"]
        app.launch()

        let table = app.tables[LeakHarnessTableId]
        XCTAssertTrue(table.waitForExistence(timeout: 10),
                      "Leak-harness table didn't appear — DemoAppSwift may not have entered --leak-harness mode")

        // Match Android harness: 20 swipes with 300 ms pauses.
        // The longer inter-swipe pause gives the SDK time to drain the
        // upload queue between swipes — at 60 fps the encode+upload
        // pipeline saturates quickly and frames are lost if swipes fire
        // too fast. 300 ms ≈ 18 frames of headroom each gap.
        for _ in 0..<20 {
            table.swipeUp(velocity: .slow)
            usleep(300_000) // 300 ms between swipes
        }

        // Extended wait: the upload queue can hold many 60fps frames;
        // 30 s gives the SDK enough time to drain it before the mock
        // server is killed. Android uses 2 s but its SDK batches frames
        // more aggressively — iOS needs more headroom.
        usleep(30_000_000) // 30 s
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
}
