//
//  NativeCrashUITests.swift
//  CrashE2EUITests
//
//  Signals, reported by the next launch as the signal, with Android's code names and only the
//  crashed thread.
//

import XCTest

final class NativeCrashUITests: CrashE2ETestCase {

    private func assertReported(_ kind: String, exceptionType expected: String, messageIn messages: [String],
                                file: StaticString = #filePath, line: UInt = #line) {
        crash(kind)
        relaunch()
        let crash = awaitCrashes(1)[0]
        XCTAssertEqual(exceptionType(crash), expected, file: file, line: line)
        XCTAssertEqual(errorType(crash), expected, file: file, line: line)
        XCTAssertTrue(messages.contains(message(crash) ?? ""), "message \(message(crash) ?? "nil")", file: file, line: line)
        XCTAssertEqual(threads(crash).count, 1, "only the crashed thread", file: file, line: line)
    }

    func testCrashTheMomentTheSdkIsInitialized_isSentByTheNextLaunch_inTheSessionItHappenedIn() {
        crashAtStart("crashAfterInit:signal")
        relaunch()
        let crash = awaitCrashes(1)[0]
        XCTAssertNotNil(session(crash))
        XCTAssertNotEqual(session(crash), sessionId())
    }

    func testAbort_isSentAsSIGABRT() { assertReported("abort", exceptionType: "SIGABRT", messageIn: ["SIGABRT"]) }
    func testSigbus_isSentAsItsSignal() {
        assertReported("sigbus", exceptionType: "SIGBUS",
                       messageIn: ["SIGBUS", "SIGBUS (BUS_ADRERR)", "SIGBUS (BUS_OBJERR)", "SIGBUS (BUS_ADRALN)"])
    }
    func testSigill_isSentAsItsSignal() {
        assertReported("sigill", exceptionType: "SIGILL",
                       messageIn: ["SIGILL", "SIGILL (ILL_ILLOPC)", "SIGILL (ILL_ILLOPN)", "SIGILL (ILL_ILLTRP)"])
    }
    func testSigtrap_isSentAsItsSignal() {
        assertReported("sigtrap", exceptionType: "SIGTRAP", messageIn: ["SIGTRAP", "SIGTRAP (TRAP_BRKPT)"])
    }
    /// arm64 does not trap integer division: the signal is sent with pthread_kill.
    func testSigfpe_isSentAsItsSignal() { assertReported("sigfpe", exceptionType: "SIGFPE", messageIn: ["SIGFPE"]) }

    func testCrashOnAPthreadTheAppStarted_isSentWithThatThreadAlone() {
        assertReported("pthread", exceptionType: "SIGSEGV", messageIn: Self.nullWriteMessages)
        XCTAssertEqual(error(endpoint.crashes[0])["triggered_by_thread"] as? Int, 0)
    }

    func testSignalTheProcessSurvives_isDroppedWithoutBeingSent() {
        launch(["hooks": ["reset"], "actions": ["crash:survivableSignal"]])
        relaunch()
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
    }

    func testSignalIgnoreErrorsFiltersOut_isDeletedWithoutBeingSent() {
        crash("signal", ["ignoreErrors": ["SIGSEGV.*"]])
        relaunch(["ignoreErrors": ["SIGSEGV.*"]])
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
        XCTAssertTrue(storedCrashes().isEmpty)
    }

    func testSignalBeforeSendDrops_isDeletedWithoutBeingSent() {
        crash("signal", ["crashBeforeSend": "drop"])
        relaunch(["crashBeforeSend": "drop"])
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
        XCTAssertTrue(storedCrashes().isEmpty)
    }

    func testSignalInASampledInSession_isSentByASampledOutLaunch() {
        crash("signal", ["sessionSampleRate": 100])
        relaunch(["sessionSampleRate": 0])
        awaitCrashes(1)
    }

    /// The handler is in from image load whatever the roll, so the report is written; recovery
    /// drops it, and nothing is sent.
    func testSignalInASampledOutSession_isNeverSent() {
        crash("signal", ["sessionSampleRate": 0])
        relaunch(["sessionSampleRate": 100])
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
    }

    func testSignalInAHybridApp_isSentOnce_withoutItsBeforeSend() {
        let hybrid: [String: Any] = ["hybridBeforeSend": true, "hybridEdit": true]
        crash("signal", hybrid)
        relaunch(hybrid)
        XCTAssertTrue(Self.nullWriteMessages.contains(message(awaitCrashes(1)[0]) ?? ""))
        settle()
        XCTAssertEqual(endpoint.crashes.count, 1)
    }

    func testSignal_isFiledUnderTheAppVersionItHappenedIn() {
        crash("signal", ["appVersion": "crash-old"])
        relaunch(["appVersion": "crash-new"])
        XCTAssertEqual(appVersion(awaitCrashes(1)[0]), "crash-old")
    }
}
