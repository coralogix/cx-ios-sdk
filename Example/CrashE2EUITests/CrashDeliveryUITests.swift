//
//  CrashDeliveryUITests.swift
//  CrashE2EUITests
//
//  How a stored crash is delivered: once, in a request of its own, finished with on a 2xx or a
//  refusal, and never re-sent by a launch after it is finished.
//

import XCTest

final class CrashDeliveryUITests: CrashE2ETestCase {

    func testHybridCrash_isSentByTheProcessThatReportedIt_andNotAgain() {
        launch(["hooks": ["reset"], "actions": ["hybridCrash"]])
        awaitCrashes(1)
        relaunch()
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1)
        XCTAssertTrue(storedCrashes().isEmpty)
    }

    func testHybridCrashWhoseLiveUploadFails_isNotSentByTheNextLaunch() {
        endpoint.answerCrashes([.status(503)])
        launch(["hooks": ["reset"], "actions": ["hybridCrash"]])
        awaitCrashes(1)
        relaunch()
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1, "a hybrid crash keeps nothing on disk")
    }

    func testCrash_isSentOnceByTheNextLaunch_inARequestOfItsOwn() {
        crash("exception", before: ["error:a live error"])
        relaunch(["actions": ["error:another live error"]])

        awaitCrashes(1)
        settle()
        let crashRequest = endpoint.crashRequests[0]
        XCTAssertEqual(crashRequest.events.count, 1, "nothing else in the crash's request")
        XCTAssertEqual(endpoint.crashes.count, 1)
    }

    private func assertSentOnceAndDropped(status: Int, file: StaticString = #filePath, line: UInt = #line) {
        endpoint.answerCrashes([.status(status)])
        crash("exception")
        relaunch()
        awaitCrashes(1)
        pause(45)  // past the +30 s slot, with its margin
        XCTAssertEqual(endpoint.crashes.count, 1, "HTTP \(status) is final", file: file, line: line)
        XCTAssertTrue(storedCrashes().isEmpty, file: file, line: line)
    }

    func testCrashAnswered400_isSentOnce_andDropped() { assertSentOnceAndDropped(status: 400) }
    func testCrashAnswered413_isSentOnce_andDropped() { assertSentOnceAndDropped(status: 413) }
    func testCrashAnswered401_isSentOnce_andDropped() { assertSentOnceAndDropped(status: 401) }
    func testCrashAnswered403_isSentOnce_andDropped() { assertSentOnceAndDropped(status: 403) }

    func testCrashWhoseUploadFailed_isSentAgainAbout30SecondsLater() {
        endpoint.answerCrashes([.status(503)])
        crash("exception")
        relaunch()

        awaitCrashes(2, timeout: 60)
        let arrivals = endpoint.crashRequests.map(\.arrival)
        assertSent(after: arrivals[1].timeIntervalSince(arrivals[0]), inSlot: 30)
        XCTAssertTrue(storedCrashes().isEmpty, "delivered the second time")
    }

    func testLaunchThatDiesMidUpload_leavesTheCrashAsItWas_forTheNextLaunch() {
        storeCrash()
        relaunch()
        let crashes = awaitCrashes(2)
        XCTAssertEqual(message(crashes[1]), message(crashes[0]), "the same crash, sent again whole")
        XCTAssertTrue(waitFor { self.storedCrashes().isEmpty })
    }

    func testCrashIgnoreErrorsFiltersOut_isNeitherSentNorKept() {
        crash("exception", ["ignoreErrors": ["NSInvalidArgumentException:.*"]])
        relaunch(["ignoreErrors": ["NSInvalidArgumentException:.*"]])
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
        XCTAssertTrue(storedCrashes().isEmpty)
    }

    func testCrashFromASampledOutSession_isNeitherSentNorKept() {
        crash("exception", ["sessionSampleRate": 0])
        relaunch(["sessionSampleRate": 100])
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
        XCTAssertTrue(storedCrashes().isEmpty)
    }

    func testCrashBeforeSendDrops_isNotSent_andNotKept() {
        crash("exception", ["crashBeforeSend": "drop"])
        relaunch(["crashBeforeSend": "drop"])
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
        XCTAssertTrue(storedCrashes().isEmpty)
    }

    /// Twelve launches crash right after init while every send fails; the ten newest are kept.
    func testCrashLoop_keepsTheLatestTen_eachSentInARequestOfItsOwn() {
        endpoint.answerCrashes([], then: .status(503))
        for index in 0..<12 {
            crash("signal", fresh: index == 0)
        }
        endpoint.answerCrashes([], then: .ok)
        let sentBefore = endpoint.crashRequests.count
        relaunch()

        XCTAssertTrue(waitFor(timeout: 60) { self.endpoint.crashRequests.count - sentBefore >= 10 })
        settle()
        let delivered = endpoint.crashRequests.dropFirst(sentBefore)
        XCTAssertEqual(delivered.count, 10)
        XCTAssertTrue(delivered.allSatisfy { $0.crashes.count == 1 })
        XCTAssertTrue(storedCrashes().isEmpty)
    }

    func testCrashLoop_doesNotPushOutAStoredFatalHang() {
        endDuringHang()
        endpoint.answerCrashes([], then: .status(503))
        for _ in 0..<11 {
            crash("signal", fresh: false)
        }
        endpoint.answerCrashes([], then: .ok)
        let sentBefore = endpoint.crashRequests.count
        relaunch()

        XCTAssertTrue(waitFor(timeout: 60) { self.endpoint.crashRequests.count - sentBefore >= 11 })
        let delivered = endpoint.crashRequests.dropFirst(sentBefore).flatMap(\.crashes)
        XCTAssertEqual(delivered.filter { errorType($0) == "ANR" }.count, 1, "the hang survives the native cap")
        XCTAssertEqual(delivered.filter { errorType($0) != "ANR" }.count, 10)
        XCTAssertEqual(errorType(delivered.last ?? [:]), "ANR", "sent after the native crashes")
    }

    func testCrashStoredByThePreviousVersion_isDeletedUnsent() {
        launch(["hooks": ["reset", "seedLegacyHybridStore"]])
        settle()
        relaunch()
        settle()
        XCTAssertFalse(endpoint.events.contains { message($0) == "legacy hybrid crash" })
    }
}
