//
//  CrashDeliveryLimitsUITests.swift
//  CrashE2EUITests
//
//  Retryable answers, Retry-After, and the limits after which a crash is given up.
//

import XCTest

final class CrashDeliveryLimitsUITests: CrashE2ETestCase {

    private func assertRetriedAfter30Seconds(status: Int, file: StaticString = #filePath, line: UInt = #line) {
        endpoint.answerCrashes([.status(status)])
        crash("exception")
        relaunch()
        awaitCrashes(2, timeout: 60)
        let arrivals = endpoint.crashRequests.map(\.arrival)
        assertSent(after: arrivals[1].timeIntervalSince(arrivals[0]), inSlot: 30, file: file, line: line)
        XCTAssertTrue(storedCrashes().isEmpty, file: file, line: line)
    }

    func testCrashAnswered408_isSentAgainAbout30SecondsLater_untilAccepted() { assertRetriedAfter30Seconds(status: 408) }
    func testCrashAnswered429_isSentAgainAbout30SecondsLater_untilAccepted() { assertRetriedAfter30Seconds(status: 429) }

    func testCrashAnsweredWithRetryAfter_isNotSentAgainBeforeIt() {
        endpoint.answerCrashes([.status(503, retryAfter: "60")])
        crash("exception")
        relaunch()
        awaitCrashes(2, timeout: 80)
        let arrivals = endpoint.crashRequests.map(\.arrival)
        XCTAssertGreaterThanOrEqual(arrivals[1].timeIntervalSince(arrivals[0]), 58)
    }

    func testRetryAfterAsAnHttpDate_isHonoured() {
        endpoint.answerCrashes([.status(503, retryAfter: Endpoint.httpDate(Date(timeIntervalSinceNow: 60 + 20)))])
        crash("exception")
        relaunch()
        awaitCrashes(2, timeout: 90)
        let arrivals = endpoint.crashRequests.map(\.arrival)
        XCTAssertGreaterThanOrEqual(arrivals[1].timeIntervalSince(arrivals[0]), 50)
    }

    func testRetryAfter_holdsBackTheNextCrashToo() {
        storeCrash()
        storeCrash(fresh: false)
        endpoint.answerCrashes([.status(503, retryAfter: "60")])
        let sentBefore = endpoint.crashRequests.count
        relaunch()

        XCTAssertTrue(waitFor(timeout: 90) { self.endpoint.crashRequests.count - sentBefore >= 3 })
        let arrivals = endpoint.crashRequests.dropFirst(sentBefore).map(\.arrival)
        XCTAssertTrue(arrivals.dropFirst().allSatisfy { $0.timeIntervalSince(arrivals[0]) >= 58 },
                      "no crash goes before the Retry-After")
    }

    func testCrashIsKeptAfterItsFifteenthFailedUpload_andDroppedAfterItsSixteenth() {
        storeCrash()
        endpoint.answerCrashes([], then: .status(503))
        relaunch(["hooks": ["setFailedUploads:14"]])
        XCTAssertTrue(waitFor(timeout: 20) { self.failedUploads(self.storedCrashes().first ?? [:]) == 15 },
                      "kept after its fifteenth failure")
        kill()

        let sentBefore = endpoint.crashRequests.count
        relaunch()
        XCTAssertTrue(waitFor(timeout: 50) { self.storedCrashes().isEmpty }, "dropped after its sixteenth")
        XCTAssertEqual(endpoint.crashRequests.count - sentBefore, 1, "not sent a seventeenth time")
    }

    func testCrashJustOverSevenDaysOld_isDeletedWithoutBeingSent_whileOneJustUnderIsSent() {
        let week = 7 * 24 * 3600
        storeCrash()
        var sentBefore = endpoint.crashRequests.count
        relaunch(["hooks": ["ageCrashesBySeconds:\(week + 60)"]])
        settle()
        XCTAssertEqual(endpoint.crashRequests.count, sentBefore, "over seven days: not sent")
        XCTAssertTrue(storedCrashes().isEmpty)
        kill()

        storeCrash(fresh: false)
        sentBefore = endpoint.crashRequests.count
        relaunch(["hooks": ["ageCrashesBySeconds:\(week - 3600)"]])
        XCTAssertTrue(waitFor(timeout: 30) { self.endpoint.crashRequests.count > sentBefore }, "under seven days: sent")
    }
}
