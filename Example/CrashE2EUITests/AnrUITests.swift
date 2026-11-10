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
}
