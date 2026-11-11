//
//  CrashSendScheduleUITests.swift
//  CrashE2EUITests
//
//  Android's schedule: one crash at a time, retried at +30 s and +2 min from the first failed
//  send, then left for the next launch.
//

import XCTest

final class CrashSendScheduleUITests: CrashE2ETestCase {

    func testCrashWhoseUploadsFail_isSentAgainAfter30SecondsAnd2Minutes_thenLeftForLater() {
        endpoint.answerCrashes([], then: .status(503))
        crash("exception")
        relaunch()

        awaitCrashes(3, timeout: 160)
        pause(20)
        let arrivals = endpoint.crashRequests.map(\.arrival)
        XCTAssertEqual(arrivals.count, 3)
        assertSent(after: arrivals[1].timeIntervalSince(arrivals[0]), inSlot: 30)
        assertSent(after: arrivals[2].timeIntervalSince(arrivals[0]), inSlot: 120)
        XCTAssertEqual(failedUploads(storedCrashes().first ?? [:]), 3, "kept, three failures counted")
    }

    func testCrashWhoseUploadGetsNoAnswer_isCountedAsFailed_andSentAgainOnceItTimesOut() {
        endpoint.answerCrashes([.noAnswer])
        crash("exception")
        relaunch()

        awaitCrashes(2, timeout: 160)
        let arrivals = endpoint.crashRequests.map(\.arrival)
        // The 45 s request timeout lands past the +30 s slot, so the retry is the +2 min one.
        assertSent(after: arrivals[1].timeIntervalSince(arrivals[0]), inSlot: 120)
    }

    func testCrashesBehindAnUnansweredUpload_waitForIt_thenGoOneAtATime() {
        storeCrash()
        storeCrash(fresh: false)
        endpoint.answerCrashes([Endpoint.Answer(delay: 10)])
        let sentBefore = endpoint.crashRequests.count
        relaunch()

        XCTAssertTrue(waitFor(timeout: 40) { self.endpoint.crashRequests.count - sentBefore >= 2 })
        let arrivals = endpoint.crashRequests.dropFirst(sentBefore).map(\.arrival)
        XCTAssertGreaterThanOrEqual(arrivals[1].timeIntervalSince(arrivals[0]), 9.5, "the second waits for the first's answer")
    }

    func testAnswerAfterTheSlot_skipsThatSlot() {
        endpoint.answerCrashes([Endpoint.Answer(status: 503, delay: 40)])
        crash("exception")
        relaunch()

        awaitCrashes(2, timeout: 160)
        let arrivals = endpoint.crashRequests.map(\.arrival)
        assertSent(after: arrivals[1].timeIntervalSince(arrivals[0]), inSlot: 120, "the +30 s slot had passed")
    }

    func testBackgroundedApp_keepsSendingUnderItsBackgroundTask() {
        endpoint.answerCrashes([.status(503)])
        crash("exception")
        relaunch()
        awaitCrashes(1)
        XCUIDevice.shared.press(.home)

        awaitCrashes(2, timeout: 60)
        let arrivals = endpoint.crashRequests.map(\.arrival)
        assertSent(after: arrivals[1].timeIntervalSince(arrivals[0]), inSlot: 30)
        XCTAssertTrue(anrs.isEmpty, "time in the background is not a hang")
    }
}
