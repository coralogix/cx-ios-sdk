//
//  CrashTerminateHandlerTests.swift
//
//  An uncaught C++ exception reaches PLCrashReporter as a bare SIGABRT. The terminate handler
//  records its type and `what()` in the crash context first, so the crash is reported as
//  `std::runtime_error: boom`. Custom data is process-wide, so each test puts back what it found.
//

import XCTest
import CrashReporter
import CoralogixInternal
#if canImport(CoralogixBootstrap)
import CoralogixBootstrap
#endif

@testable import Coralogix

/// A SIGABRT report carrying `customData`, as an uncaught C++ exception leaves one.
private struct AbortReport: CrashReportReading {
    var customData: Data?
    var reportId: String? = "5E1F0A2B-3C4D-4E5F-8061-728394A5B6C7"
    var timestamp: Date? = Date(timeIntervalSince1970: 1_700_000_000)
    var signalName = "SIGABRT"
    var signalCode: String? = "#0"
    var exceptionName: String?
    var exceptionReason: String?
    var processName: String? = "HostApp"
    var processID: UInt = 4242
    var processStartTime: Date?
    var applicationIdentifier: String? = "com.example.host"
    var threads: [CrashThread] = [
        CrashThread(number: 0, crashed: false, frames: [Self.frame(0)]),
        CrashThread(number: 1, crashed: true, frames: [Self.frame(0), Self.frame(1)])
    ]
    var mainBinaryImage: (baseAddress: String, arch: String)? = ("0x100000000", "arm64")

    static func frame(_ number: Int) -> CrashStackFrame {
        CrashStackFrame(frameNumber: "\(number)", binary: "HostApp", functionAddressCalled: "0x100000010",
                        base: "0x100000000", offset: "16")
    }
}

final class CrashTerminateHandlerTests: XCTestCase {

    private var savedSections: [String: Any] = [:]
    private var savedReporter: PLCrashReporter?

    private let session: [String: Any] = [
        Keys.sessionId.rawValue: "c2a1f0de-0000-4000-8000-000000000002",
        Keys.crashContextSessionCreationTime.rawValue: 1_700_000_000_123,
        Keys.spanSessionSampledIn.rawValue: true
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedSections = CRXCrashContext.sections
        savedReporter = try XCTUnwrap(CRXCrashContext.activeReporter, "+load enabled a reporter in the test process")
        CRXCrashContext.setSection(Keys.crashContextSession.rawValue, value: session)
    }

    override func tearDownWithError() throws {
        // Setting the reporter writes the envelope from the sections again, without the cxx section.
        CRXCrashContext.activeReporter = savedReporter
        for name in CRXCrashContext.sections.keys where savedSections[name] == nil {
            CRXCrashContext.setSection(name, value: nil)
        }
        for (name, value) in savedSections {
            CRXCrashContext.setSection(name, value: value as? [String: Any])
        }
        try super.tearDownWithError()
    }

    private func writtenContext() -> CrashContextEnvelope? {
        CrashContextEnvelope(data: savedReporter?.customData)
    }

    // MARK: - Installation

    /// `+load` installs it before reading `CoralogixDisableEarlyCrashHandler`, so it is installed
    /// whatever that key says.
    func test_isInstalledAtLoad() {
        XCTAssertTrue(CRXTerminateHandler.isInstalled)
    }

    func test_aSecondInstall_changesNothing_andNeverHandsOverToItself() {
        XCTAssertFalse(CRXTerminateHandler.install())
        XCTAssertTrue(CRXTerminateHandler.isInstalled)
        XCTAssertFalse(CRXTerminateHandler.handsOverToItself)
    }

    // MARK: - Recording

    func test_aRuntimeError_isCarriedByTheNextReport_withTheSession() throws {
        XCTAssertTrue(CRXTerminateHandler.recordRuntimeErrorForTesting("boom"))

        let context = try XCTUnwrap(CrashContextEnvelope(data: try CrashContextTests.liveReport().customData))
        XCTAssertEqual(context.cxx, .init(type: "St13runtime_error", what: "boom"))
        XCTAssertEqual(context.session?.id, "c2a1f0de-0000-4000-8000-000000000002")
    }

    func test_aRecordedRuntimeError_mapsToItsTypeAndWhat_signalShaped() throws {
        XCTAssertTrue(CRXTerminateHandler.recordRuntimeErrorForTesting("boom"))

        let crash = CrashReportMapper.map(AbortReport(customData: savedReporter?.customData))

        XCTAssertEqual(crash.kind, .cxx)
        XCTAssertEqual(crash.errorMessage, "std::runtime_error: boom")
        XCTAssertEqual(crash.exceptionType, "SIGABRT")
        XCTAssertEqual(crash.errorType, "SIGABRT")
        let threads = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(crash.threadsJSON.utf8)) as? [String])
        XCTAssertEqual(threads.count, 1, "a C++ crash sends only the crashed thread, as a native crash does")
        XCTAssertEqual(crash.triggeredByThread, 0)
    }

    func test_withoutAReporterOfOurs_nothingIsWritten() {
        CRXCrashContext.activeReporter = nil

        XCTAssertFalse(CRXTerminateHandler.recordRuntimeErrorForTesting("boom"))
        XCTAssertNil(writtenContext()?.cxx)
    }

    func test_anObjectiveCException_isLeftToPLCrashReporter() {
        XCTAssertFalse(CRXTerminateHandler.recordObjCExceptionForTesting())
        XCTAssertNil(writtenContext()?.cxx)
        XCTAssertNotNil(writtenContext()?.session)
    }

    // MARK: - The envelope written at terminate

    func test_whatIsEscaped_andCutAtACharacterBoundary() throws {
        let what = "say \"hi\"\\\n\t" + String(repeating: "é", count: 200)
        let data = try XCTUnwrap(CRXCrashContext.envelope(withCxxType: "St13runtime_error", what: what))

        let context = try XCTUnwrap(CrashContextEnvelope(data: data), "still valid JSON")
        let recorded = try XCTUnwrap(context.cxx?.what)
        XCTAssertTrue(recorded.hasPrefix("say \"hi\"\\\n\t"))
        XCTAssertEqual(recorded.utf8.count, 255, "256 bytes allowed: 11 ASCII, then 122 two-byte é")
        XCTAssertTrue(recorded.hasSuffix("é"))
        XCTAssertEqual(context.session?.id, "c2a1f0de-0000-4000-8000-000000000002")
    }

    func test_withNoEnvelopeYet_theSectionStandsAlone() throws {
        for name in CRXCrashContext.sections.keys {
            CRXCrashContext.setSection(name, value: nil)
        }

        let data = try XCTUnwrap(CRXCrashContext.envelope(withCxxType: "St9bad_alloc", what: nil))
        let context = try XCTUnwrap(CrashContextEnvelope(data: data))
        XCTAssertEqual(context.cxx, .init(type: "St9bad_alloc", what: nil))
        XCTAssertNil(context.session)
    }

    // MARK: - Mapping

    func test_aTypeWithoutWhat_isTheDemangledTypeAlone() {
        let data = Data(#"{"v":1,"cxx":{"type":"St9bad_alloc"}}"#.utf8)
        XCTAssertEqual(CrashReportMapper.map(AbortReport(customData: data)).errorMessage, "std::bad_alloc")
    }

    func test_aTypeThatDoesNotDemangle_isSentAsItIs() {
        let data = Data(#"{"v":1,"cxx":{"type":"not a mangled name","what":"x"}}"#.utf8)
        XCTAssertEqual(CrashReportMapper.map(AbortReport(customData: data)).errorMessage, "not a mangled name: x")
    }

    func test_aLongWhat_isCutTo102Units_withTheTypeCounted() {
        let data = Data(#"{"v":1,"cxx":{"type":"St13runtime_error","what":"\#(String(repeating: "x", count: 300))"}}"#.utf8)
        let message = CrashReportMapper.map(AbortReport(customData: data)).errorMessage
        XCTAssertEqual(message.utf16.count, 102)
        XCTAssertTrue(message.hasPrefix("std::runtime_error: xxx"))
    }

    func test_anUnreadableCxxSection_fallsBackToTheBareSignal() {
        let data = Data(#"{"v":1,"cxx":{"type":5}}"#.utf8)
        let crash = CrashReportMapper.map(AbortReport(customData: data))
        XCTAssertEqual(crash.kind, .signal)
        XCTAssertEqual(crash.errorMessage, "SIGABRT")
    }
}
