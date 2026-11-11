//
//  CrashEdgeCaseUITests.swift
//  CrashE2EUITests
//
//  The edges of what counts as one crash: when it happened, launches that end without one, two
//  crashes in one launch or around init, and a crash while session replay records.
//

import XCTest

final class CrashEdgeCaseUITests: CrashE2ETestCase {

    func testRecoveredCrash_isTimedWhenItHappened_notWhenTheAppRelaunched() throws {
        crash("exception")
        let crashed = Date()
        idle(8)
        let relaunched = Date()
        relaunch()

        let crash = awaitCrashes(1)[0]
        let timestamp = try XCTUnwrap((crash["timestamp"] as? NSNumber)?.doubleValue, "no timestamp") / 1000
        let crashTimestamp = try XCTUnwrap((error(crash)["crash_timestamp"] as? String).flatMap(Double.init), "no crash_timestamp") / 1000
        // The crash report keeps its time to the second, and the app is seen gone a moment after.
        XCTAssertEqual(timestamp, crashed.timeIntervalSince1970, accuracy: 3, "the event is timed at the crash")
        XCTAssertEqual(timestamp, crashTimestamp, accuracy: 1, "the event's time and the crash's agree")
        XCTAssertGreaterThan(relaunched.timeIntervalSince1970 - timestamp, 6, "well before the relaunch")
    }

    func testAppThatExitsNormally_isNotReportedAsACrashOrAHang() {
        launch(["hooks": ["reset"], "actions": ["wait:1000", "crash:exit"]], waitForActions: false)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "the app did not exit")
        assertNextLaunchReportsNothing(after: "a normal exit")
    }

    func testAppTerminatedWhileIdle_isNotReportedAsACrashOrAHang() {
        launch(["hooks": ["reset"], "actions": ["wait:1000"]])
        idle(3)
        kill()
        assertNextLaunchReportsNothing(after: "a termination while idle")
    }

    func testCrashBeforeInit_thenOneAfterInitOnTheNextLaunch_onlyTheSecondIsSent() {
        // The kind is not reached: each launch crashes as it starts.
        crash("exception", ["appStart": "crashBeforeInit:exception"])
        crash("signal", ["appStart": "crashAfterInit:signal"], fresh: false)
        relaunch()

        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(exceptionType(crash), "SIGSEGV")
        XCTAssertTrue(Self.nullWriteMessages.contains(message(crash) ?? ""), message(crash) ?? "nil")
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1, "the crash before init is not sent")
    }

    func testTwoThreadsCrashingAtOnce_areOneCrashEvent() {
        crash("twoThreads")
        relaunch()

        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(exceptionType(crash), "SIGSEGV")
        XCTAssertTrue(Self.nullWriteMessages.contains(message(crash) ?? ""), message(crash) ?? "nil")
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1)
    }

    func testCrashWhileSessionReplayRecords_isSentOnce_inTheSessionItHappenedIn() throws {
        crash("exception", before: ["error:while recording"], ["sessionReplay": true])
        let live = try XCTUnwrap(endpoint.events.first { message($0) == "while recording" }, "the live error did not arrive")
        // Not asserted: `hasRecording` turns true on the first captured frame, and CI's simulators
        // give the app no Metal device, so they capture none. Replay is started either way.
        relaunch(["sessionReplay": true])

        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(message(crash), "NSInvalidArgumentException: crash e2e exception")
        XCTAssertEqual(session(crash), session(live))
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1, "sent once")
    }

    func testHybridCrashThenRCTFatalException_inOneLaunch_areOneCrashEvent() {
        crash("rctFatal", before: ["hybridCrash"])
        relaunch()

        awaitCrashes(2)
        settle()
        let crashes = endpoint.crashes
        XCTAssertTrue(crashes.contains { message($0) == "crash e2e: hybrid crash" }, "the hybrid crash was sent live")
        XCTAssertTrue(crashes.contains { message($0) == "RCTFatalException: Unhandled JS Exception: TypeError: crash e2e" },
                      "the native exception was sent by the next launch")
        // Strict: the test fails once the two are de-duplicated, so this marker cannot outlive it.
        let gap = XCTExpectedFailure.Options()
        gap.issueMatcher = { $0.compactDescription.contains("one event per JS fatal") }
        XCTExpectFailure("a JS fatal is reported by the hybrid crash and again by the RCTFatalException it raises: "
                         + "neither platform de-duplicates the two yet (moved to the backlog)", options: gap) {
            XCTAssertEqual(crashes.count, 1, "one event per JS fatal")
        }
    }

    // MARK: -

    /// The next launch, after one that ended without a crash, sends its own events and no crash or hang.
    private func assertNextLaunchReportsNothing(after ending: String, file: StaticString = #filePath, line: UInt = #line) {
        relaunch(["actions": ["error:after \(ending)"]])
        XCTAssertTrue(waitFor(timeout: 15) { self.endpoint.events.contains { self.message($0) == "after \(ending)" } },
                      "the next launch's own error did not arrive", file: file, line: line)
        settle()
        XCTAssertEqual(endpoint.crashes.count, 0, "crashes after \(ending)", file: file, line: line)
        XCTAssertEqual(anrs.count, 0, "hangs after \(ending)", file: file, line: line)
    }

    private func idle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }
}
