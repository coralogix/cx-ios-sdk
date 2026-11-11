//
//  AnrUITests.swift
//  CrashE2EUITests
//
//  A main thread blocked for 5 s is one ANR, sent by the app as it happens; one the launch ends
//  during is reported by the next launch, unless its own event got out.
//

import XCTest

final class AnrUITests: CrashE2ETestCase {

    func testHangTheAppRecoversFrom_isSentOnce_byItsOwnEvent_withAndroidsMessage_andEveryThread() {
        launch(["hooks": ["reset"], "actions": ["wait:1000", "hang:6500", "wait:3000"]])

        XCTAssertTrue(waitFor(timeout: 20) { !self.anrs.isEmpty })
        let anr = anrs[0]
        XCTAssertEqual(message(anr), "Application Not Responding for at least 1000 ms.")
        XCTAssertEqual(isCrash(anr), false)
        XCTAssertGreaterThan(threads(anr).count, 1)

        relaunch()
        settle()
        XCTAssertEqual(anrs.count, 1, "nothing more on the next launch")
    }

    func testFourSecondHang_isNotReported() {
        launch(["hooks": ["reset"], "actions": ["wait:1000", "hang:4000", "wait:2000"]])
        settle(4)
        XCTAssertTrue(anrs.isEmpty)
    }

    func testTwoHangs_areTwoAnrs() {
        launch(["hooks": ["reset"], "actions": ["wait:1000", "hang:6500", "wait:1500", "hang:6500", "wait:3000"]])
        XCTAssertTrue(waitFor(timeout: 20) { self.anrs.count >= 2 })
        settle(4)
        XCTAssertEqual(anrs.count, 2)
    }

    func testHangWithAnrsSwitchedOff_isNotSent_whenTheLaunchEndsDuringIt() {
        endDuringHang(["anrInstrumentation": false])
        relaunch(["anrInstrumentation": false])
        settle()
        XCTAssertTrue(anrs.isEmpty)
    }

    func testHangIgnoreErrorsNames_isNotSent_whenTheLaunchEndsDuringIt() {
        endDuringHang(["ignoreErrors": ["ANR"]])
        relaunch(["ignoreErrors": ["ANR"]])
        settle()
        XCTAssertTrue(anrs.isEmpty)
    }

    func testHangInASampledOutSession_isNotSent_whenTheLaunchEndsDuringIt() {
        endDuringHang(["sessionSampleRate": 0])
        relaunch(["sessionSampleRate": 100])
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
    }

    func testHangInASampledInSession_isSentByASampledOutLaunch_whenTheLaunchEndsDuringIt() {
        endDuringHang(["sessionSampleRate": 100])
        relaunch(["sessionSampleRate": 0])
        let anr = awaitCrashes(1)[0]
        XCTAssertEqual(errorType(anr), "ANR")
    }

    func testFatalHang_startsATraceOfItsOwn() {
        endDuringHang(["actions": []])
        let launchTraces = Set(endpoint.events.compactMap(traceId))
        relaunch()
        let anr = awaitCrashes(1)[0]
        XCTAssertNotNil(traceId(anr))
        XCTAssertFalse(launchTraces.contains(traceId(anr) ?? ""))
    }

    // MARK: - Background, setup and options

    /// Time spent in the background is not a hang: twice away for longer than the threshold, and
    /// back. The watchdog still runs after it: a hang then is one ANR.
    func testReturningFromTheBackground_isNotAnAnr_butAHangAfterIt_isOne() {
        launch(["hooks": ["reset"], "actions": ["wait:1000"]])
        for _ in 0..<2 {
            XCUIDevice.shared.press(.home)
            settle(10)
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            // Live events go out every 2 s: one reported on the way back has arrived by now.
            settle(4)
        }
        XCTAssertTrue(anrs.isEmpty, "\(anrs.count) ANR(s) for time spent in the background")

        app.buttons["e2e.hang"].tap()
        XCTAssertTrue(waitFor(timeout: 20) { !self.anrs.isEmpty })
        settle(4)
        XCTAssertEqual(anrs.count, 1)
        XCTAssertEqual(isCrash(anrs[0]), false)
    }

    /// React Native sets the SDK up off the main thread.
    func testHangInAnAppThatSetsUpTheSdkOffTheMainThread_isOneAnr_withEveryThread() {
        launch(["hooks": ["reset"], "appStart": "initializeOffMain", "actions": ["wait:2000", "hang:6500", "wait:3000"]])

        XCTAssertTrue(waitFor(timeout: 20) { !self.anrs.isEmpty })
        settle(4)
        XCTAssertEqual(anrs.count, 1)
        XCTAssertEqual(isCrash(anrs[0]), false)
        XCTAssertGreaterThan(threads(anrs[0]).count, 1)
    }

    func testHangFromTheColdLaunch_theLaunchEndsDuring_isSentOnceByTheNextLaunch() {
        endpoint.answerLive(.noAnswer)
        launch(["hooks": ["reset"], "appStart": "hangAfterInit"], waitForActions: false)
        settle(8)
        kill()
        endpoint.answerLive(.ok)

        relaunch()
        let anr = awaitCrashes(1)[0]
        XCTAssertEqual(errorType(anr), "ANR")
        XCTAssertEqual(isCrash(anr), true)
        relaunch()
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1, "not sent again")
    }

    /// Hangs follow the `.anr` switch alone.
    func testHangWithErrorsSwitchedOff_isSentByItsOwnEvent() {
        launch(["hooks": ["reset"], "errorInstrumentation": false, "actions": ["wait:1000", "hang:6500", "wait:3000"]])

        XCTAssertTrue(waitFor(timeout: 20) { !self.anrs.isEmpty })
        XCTAssertEqual(isCrash(anrs[0]), false)
    }

    func testHangWithErrorsSwitchedOff_isSentByTheNextLaunch_whenTheLaunchEndsDuringIt() {
        endDuringHang(["errorInstrumentation": false])
        relaunch(["errorInstrumentation": false])

        let anr = awaitCrashes(1)[0]
        XCTAssertEqual(errorType(anr), "ANR")
    }
}
