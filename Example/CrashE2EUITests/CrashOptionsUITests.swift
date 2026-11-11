//
//  CrashOptionsUITests.swift
//  CrashE2EUITests
//
//  The customer's options as a stored crash meets them: ignoreErrors, the error switch,
//  beforeSend, sampling, the hybrid round trip, the app version and tracesExporter.
//

import XCTest

final class CrashOptionsUITests: CrashE2ETestCase {

    func testException_ignoreErrorsNamingItInAnotherCase_isNeitherSentNorKept() {
        let options: [String: Any] = ["ignoreErrors": ["nsinvalidargumentexception:.*"]]
        crash("exception", options)
        relaunch(options)
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
        XCTAssertTrue(storedCrashes().isEmpty)
    }

    func testCrashWithErrorsSwitchedOff_isNeitherSentNorKept() {
        let options: [String: Any] = ["errorInstrumentation": false]
        crash("exception", options)
        relaunch(options)
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
        XCTAssertTrue(storedCrashes().isEmpty)
    }

    func testCrashBeforeSendEdits_isSentAsEdited_once() {
        crash("exception", ["crashBeforeSend": "edit"])
        relaunch(["crashBeforeSend": "edit"])
        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(message(crash), "edited in beforeSend")
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1)
    }

    func testExceptionInASampledInSession_isSentByASampledOutLaunch() {
        crash("exception", ["sessionSampleRate": 100])
        relaunch(["sessionSampleRate": 0])
        awaitCrashes(1)
    }

    /// A crash skips the hybrid round trip: a hybrid beforeSend never sees it.
    func testHybridCrash_isSentLive_withoutTheHybridBeforeSend() {
        launch(["hooks": ["reset"], "hybridBeforeSend": true, "hybridEdit": true,
                "actions": ["error:a live error", "hybridCrash"]])
        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(message(crash), "crash e2e: hybrid crash")
        XCTAssertTrue(waitFor { self.endpoint.events.contains { self.message($0) == "edited in hybrid beforeSend" } },
                      "control: the round trip edits a non-crash error")
        relaunch(["hybridBeforeSend": true, "hybridEdit": true])
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1)
    }

    func testExceptionInAHybridApp_isSentOnceByTheNextLaunch_withoutItsBeforeSend() {
        let hybrid: [String: Any] = ["hybridBeforeSend": true, "hybridEdit": true]
        crash("exception", hybrid)
        relaunch(hybrid)
        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(message(crash), "NSInvalidArgumentException: crash e2e exception")
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1)
    }

    func testException_isFiledUnderTheAppVersionItHappenedIn() {
        crash("exception", ["appVersion": "crash-old"])
        relaunch(["appVersion": "crash-new"])
        XCTAssertEqual(appVersion(awaitCrashes(1)[0]), "crash-old")
    }

    func testCrashSentTwice_reachesTheAppsTracesExporterOnce() {
        endpoint.answerCrashes([.status(503)])
        crash("exception", ["tracesExporter": true])
        relaunch(["tracesExporter": true])
        awaitCrashes(2, timeout: 60)
        pause(3)
        XCTAssertEqual(app.staticTexts["e2e.forwarded"].label, "1")
    }
}
