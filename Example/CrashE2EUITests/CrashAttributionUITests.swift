//
//  CrashAttributionUITests.swift
//  CrashE2EUITests
//
//  Smoke: crash, session, view and export together. A crash is reported as it happened: its
//  session (rotations included), its screen, its counters and its order among other crashes.
//

import XCTest

final class CrashAttributionUITests: CrashE2ETestCase {

    func testCrashAfterARotation_isSentInTheRotatedSession_onTheScreenItHappenedOn() {
        crash("exception", before: ["rotate", "error:after the rotation", "view:Second"])
        let rotated = endpoint.events.first { message($0) == "after the rotation" }.flatMap(session)
        relaunch()
        let crash = awaitCrashes(1)[0]
        XCTAssertNotNil(rotated)
        XCTAssertEqual(session(crash), rotated)
        XCTAssertEqual(view(crash), "SecondViewController")
    }

    func testCrash_carriesTheErrorCountItHappenedWith() {
        crash("exception", before: ["error:one", "error:two"])
        relaunch()
        XCTAssertEqual(errorCount(awaitCrashes(1)[0]), 3, "two errors and this crash")
    }

    func testCrashResentOnThreeLaunches_carriesTheSameErrorCount() {
        crash("exception", before: ["error:one"])
        endpoint.answerCrashes([], then: .noAnswer)
        for _ in 0..<3 {
            let before = endpoint.crashRequests.count
            launch(waitForActions: false)
            XCTAssertTrue(waitFor(timeout: 30) { self.endpoint.crashRequests.count > before })
            kill()
        }
        let counts = endpoint.crashes.map(errorCount)
        XCTAssertEqual(counts.count, 3)
        XCTAssertEqual(Set(counts.map { $0 ?? -1 }), [2])
    }

    func testCrashBeforeAnyScreen_isNotFiledUnderAScreen() {
        crashAtStart("crashAfterInit:exception")
        relaunch()
        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(view(crash), "", "filed under no screen")
    }

    func testCrashBeforeInit_isNeverSent_andTheNextLaunchsOwnEventsAreUnaffected() {
        crashAtStart("crashBeforeInit:exception")
        relaunch(["actions": ["error:after the pre-init crash"]])
        XCTAssertTrue(waitFor(timeout: 15) { self.endpoint.events.contains { self.message($0) == "after the pre-init crash" } })
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
    }

    func testThreeLaunchesThatCrashBeforeDelivery_areAllSent_newestFirst() {
        var sessions: [String] = []
        endpoint.answerCrashes([], then: .noAnswer)
        for index in 0..<3 {
            // The session is read off the screen: while a stored crash's send gets no answer,
            // this launch's own events do not leave before it crashes.
            launch(["hooks": index == 0 ? ["reset"] : [], "actions": ["wait:3000", "crash:exception"]],
                   waitForActions: false)
            XCTAssertTrue(waitFor { self.sessionId() != "none" && !self.sessionId().isEmpty })
            sessions.append(sessionId())
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "the app did not crash")
            pause(1.5)  // a report's time is kept to the second
        }
        endpoint.answerCrashes([], then: .ok)
        let before = endpoint.crashRequests.count
        relaunch()
        XCTAssertTrue(waitFor(timeout: 40) { self.endpoint.crashRequests.count - before >= 3 })
        let sent = endpoint.crashRequests.dropFirst(before).flatMap(\.crashes).compactMap(session)
        XCTAssertEqual(sent, Array(sessions.reversed()))
    }
}
