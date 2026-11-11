//
//  CrashCaptureUITests.swift
//  CrashE2EUITests
//
//  What a crash captured by PLCrashReporter reports, end to end: the next launch sends it once,
//  in the session and on the screen it happened in.
//

import XCTest

final class CrashCaptureUITests: CrashE2ETestCase {

    func testSignalCrash_isSentOnceByTheNextLaunch_asItsSignal_inTheSessionAndScreenItHappenedIn() {
        crash("signal", before: ["view:Second"])
        let crashedSession = endpoint.events.compactMap(session).first

        relaunch()

        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(exceptionType(crash), "SIGSEGV")
        XCTAssertEqual(errorType(crash), "SIGSEGV")
        XCTAssertTrue(Self.nullWriteMessages.contains(message(crash) ?? ""), message(crash) ?? "nil")
        XCTAssertEqual(session(crash), crashedSession)
        XCTAssertNotEqual(session(crash), sessionId(), "not the relaunch's session")
        XCTAssertEqual(view(crash), "SecondViewController")
        XCTAssertEqual(threads(crash).count, 1, "a signal sends only the crashed thread")
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1, "sent once")
        XCTAssertTrue(storedCrashes().isEmpty)
    }
}

extension CrashCaptureUITests {

    func testExceptionOnABackgroundThread_isSentOnceByTheNextLaunch_withThatThreadFirst_andTheMainThreadAmongTheOthers() {
        crash("backgroundException")
        relaunch()

        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(exceptionType(crash), "SIGABRT")
        XCTAssertEqual(message(crash), "NSInvalidArgumentException: crash e2e background")
        XCTAssertGreaterThan(threads(crash).count, 1, "an exception sends every thread")
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1)
    }

    func testHangTheLaunchEndsDuring_isSentOnceByTheNextLaunch() {
        endDuringHang()
        let hungSession = endpoint.events.compactMap(session).first

        relaunch()

        let anr = awaitCrashes(1)[0]
        XCTAssertEqual(errorType(anr), "ANR")
        XCTAssertEqual(message(anr), "Application Not Responding")
        XCTAssertEqual(isCrash(anr), true)
        XCTAssertEqual(session(anr), hungSession)
        XCTAssertGreaterThan(threads(anr).count, 1, "every thread, main first")
        relaunch()
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1, "sent once")
    }

    func testHangReportedByItsOwnEvent_isNotReportedAgain_whenTheLaunchEndsDuringIt() {
        endDuringHang(liveDelivered: true)
        XCTAssertEqual(anrs.filter { isCrash($0) == false }.count, 1, "the live ANR was delivered")

        relaunch()
        settle()

        XCTAssertTrue(endpoint.crashes.isEmpty)
    }

    func testHangDeliveredThroughHybridBeforeSend_isNotReportedAgain_whenTheLaunchEndsDuringIt() {
        endDuringHang(["hybridBeforeSend": true], liveDelivered: true)
        XCTAssertEqual(anrs.filter { isCrash($0) == false }.count, 1, "the live ANR came back through the round trip")

        relaunch(["hybridBeforeSend": true])
        settle()

        XCTAssertTrue(endpoint.crashes.isEmpty)
    }

    /// Only a hybrid crash is sent by the process that reports it on iOS.
    func testHybridCrashInAGlobalSpan_isSentLive_inThatSpansTrace() {
        launch(["hooks": ["reset"], "globalSpan": true, "actions": ["error:in the span", "hybridCrash"]])

        let crash = awaitCrashes(1)[0]
        let globalTrace = app.staticTexts["e2e.globalTrace"].label
        XCTAssertNotEqual(globalTrace, "none")
        XCTAssertEqual(traceId(crash), globalTrace,
                       "events: \(endpoint.events.map { "\(($0["event_context"] as? [String: Any])?["type"] ?? "?"):\(self.traceId($0) ?? "-")" })")
    }

    func testCrashInAGlobalSpan_sentByTheNextLaunch_startsATraceOfItsOwn() {
        crash("exception", before: ["error:in the span"], ["globalSpan": true])
        let inSpan = endpoint.events.first { message($0) == "in the span" }
        XCTAssertNotNil(inSpan.flatMap(traceId), "control: the error in the span got out")
        relaunch()

        let crash = awaitCrashes(1)[0]
        XCTAssertNotNil(traceId(crash))
        XCTAssertNotEqual(traceId(crash), inSpan.flatMap(traceId))
    }
}
