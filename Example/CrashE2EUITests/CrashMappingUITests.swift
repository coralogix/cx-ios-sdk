//
//  CrashMappingUITests.swift
//  CrashE2EUITests
//
//  How each kind of crash reads on the wire: signal-shaped, with what crashed as its message.
//

import XCTest

final class CrashMappingUITests: CrashE2ETestCase {

    private func reported(_ kind: String, _ fields: [String: Any] = [:]) -> [String: Any] {
        crash(kind, fields)
        relaunch(fields)
        return awaitCrashes(1)[0]
    }

    func testException_isSentAsSIGABRT_withItsNameAndReasonAsMessage() {
        let crash = reported("exception")
        XCTAssertEqual(exceptionType(crash), "SIGABRT")
        XCTAssertEqual(errorType(crash), "SIGABRT")
        XCTAssertEqual(message(crash), "NSInvalidArgumentException: crash e2e exception")
    }

    func testUnrecognizedSelector_isSentWithNSInvalidArgumentExceptionInItsMessage() {
        let crash = reported("unrecognizedSelector")
        XCTAssertTrue(message(crash)?.hasPrefix("NSInvalidArgumentException: -[NSNull length]: unrecognized selector") == true,
                      message(crash) ?? "nil")
    }

    /// Known gap: raised with a nil reason, the exception faults (SEGV_ACCERR) before
    /// PLCrashReporter records it, so the report names the fault instead. Strict: the test fails
    /// once the gap is closed, so this marker cannot outlive it.
    func testExceptionWithoutReason_isSentWithItsNameAlone() {
        XCTExpectFailure("an NSException with a nil reason is recorded as SIGSEGV (SEGV_ACCERR)") {
            XCTAssertEqual(message(reported("exceptionWithoutReason")), "NSGenericException")
        }
    }

    func testCxxException_isSentAsSIGABRT_withItsTypeAndWhat() {
        let crash = reported("cxx")
        XCTAssertEqual(exceptionType(crash), "SIGABRT")
        XCTAssertEqual(message(crash), "std::runtime_error: crash lab C++ exception")
        XCTAssertEqual(threads(crash).count, 1)
    }

    func testRCTFatalException_isSentAsSIGABRT_withRCTFatalExceptionAndItsReason() {
        let crash = reported("rctFatal")
        XCTAssertEqual(exceptionType(crash), "SIGABRT")
        XCTAssertEqual(message(crash), "RCTFatalException: Unhandled JS Exception: TypeError: crash e2e")
    }

    func testLongReason_isCutTo102Characters() {
        let text = message(reported("longReason")) ?? ""
        XCTAssertEqual(text.utf16.count, 102)
        XCTAssertTrue(text.hasPrefix("NSInternalInconsistencyException: crash e2e: a reason"))
    }

    func testSignal_carriesOnlyTheCrashedThread_andTheBaseAddressOfTheApp() {
        let crash = reported("signal")
        XCTAssertEqual(threads(crash).count, 1)
        XCTAssertNotNil(error(crash)["base_address"] as? String)
    }

    func testIgnoreErrors_matchesTheTypeInAnyCase_tryingEveryPattern() {
        crash("exception", ["ignoreErrors": ["no such error", "sigabrt"]])
        relaunch(["ignoreErrors": ["no such error", "sigabrt"]])
        settle()
        XCTAssertTrue(endpoint.crashes.isEmpty)
    }

    func testIgnoreErrors_appliesToANonCrashError() {
        launch(["hooks": ["reset"], "ignoreErrors": ["timeout"],
                "actions": ["error:Network timeout", "error:Disk full", "wait:3000"]])
        XCTAssertTrue(waitFor(timeout: 15) { self.endpoint.events.contains { self.message($0) == "Disk full" } },
                      "errors received: \(endpoint.events.compactMap(message)), events: \(endpoint.events.count)")
        XCTAssertFalse(endpoint.events.contains { message($0) == "Network timeout" })
    }
}
