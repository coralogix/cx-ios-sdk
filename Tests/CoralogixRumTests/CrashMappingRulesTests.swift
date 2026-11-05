//
//  CrashMappingRulesTests.swift
//
//  Every recovered crash is signal-shaped, as on Android: `exception_type` and `error_type` are
//  the signal, and `error_message` says what crashed — the exception's name and reason, or the
//  signal and its code. `ignoreErrors` now tries every pattern and the error type too.
//

import XCTest
import CoralogixInternal

@testable import Coralogix

private struct FakeReport: CrashReportReading {
    var reportId: String? = "0B1C2D3E-4F50-4617-8293-A4B5C6D7E8F9"
    var timestamp: Date? = Date(timeIntervalSince1970: 1_700_000_000)
    var signalName = "SIGSEGV"
    var signalCode: String? = "SEGV_MAPERR"
    var exceptionName: String?
    var exceptionReason: String?
    var processName: String? = "HostApp"
    var processID: UInt = 4242
    var applicationIdentifier: String? = "com.example.host"
    var threads: [CrashThread] = [
        CrashThread(number: 0, crashed: false, frames: frames(3, binary: "libsystem_kernel.dylib")),
        CrashThread(number: 1, crashed: false, frames: frames(250, binary: "Foundation")),
        CrashThread(number: 2, crashed: true, frames: frames(250, binary: "HostApp"))
    ]
    var mainBinaryImage: (baseAddress: String, arch: String)? = ("0x100000000", "arm64")
    var customData: Data?

    static func frames(_ count: Int, binary: String) -> [CrashStackFrame] {
        (0..<count).map {
            CrashStackFrame(frameNumber: "\($0)", binary: binary,
                            functionAddressCalled: String(format: "0x%016lx", 0x1_0000_0000 + $0 * 4),
                            base: "0x100000000", offset: "\($0 * 4)")
        }
    }

    static func nsException(reason: String? = "-[NSNull length]: unrecognized selector sent to instance 0x1f0e3c6c8") -> FakeReport {
        var report = FakeReport()
        report.signalName = "SIGABRT"
        report.signalCode = "#0"
        report.exceptionName = "NSInvalidArgumentException"
        report.exceptionReason = reason
        return report
    }
}

private func decodedThreads(_ crash: MappedCrash) throws -> [[[String: String]]] {
    let threads = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(crash.threadsJSON.utf8)) as? [String])
    return try threads.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [[String: String]]) }
}

final class CrashMappingRulesTests: XCTestCase {

    // MARK: - Uncaught NSException

    func test_nsException_isSignalShaped_withNameAndReasonAsTheMessage() {
        let crash = CrashReportMapper.map(FakeReport.nsException())

        XCTAssertEqual(crash.kind, .objcException)
        XCTAssertEqual(crash.exceptionType, "SIGABRT")
        XCTAssertEqual(crash.errorType, "SIGABRT")
        XCTAssertEqual(crash.errorMessage, "NSInvalidArgumentException: -[NSNull length]: unrecognized selector sent to instance 0x1f0e3c6c8")
    }

    func test_nsException_withoutAReason_isNamedAlone() {
        XCTAssertEqual(CrashReportMapper.map(FakeReport.nsException(reason: nil)).errorMessage, "NSInvalidArgumentException")
        XCTAssertEqual(CrashReportMapper.map(FakeReport.nsException(reason: "")).errorMessage, "NSInvalidArgumentException")
    }

    func test_nsException_sendsEveryThread_crashedFirst_eachCutTo200Frames() throws {
        let crash = CrashReportMapper.map(FakeReport.nsException())
        let threads = try decodedThreads(crash)

        XCTAssertEqual(threads.count, 3)
        XCTAssertEqual(threads[0].first?[Keys.binary.rawValue], "HostApp", "the crashed thread comes first")
        XCTAssertEqual(threads[1].first?[Keys.binary.rawValue], "libsystem_kernel.dylib")
        XCTAssertEqual(threads[2].first?[Keys.binary.rawValue], "Foundation")
        XCTAssertEqual(threads.map(\.count), [200, 3, 200])
        XCTAssertEqual(crash.triggeredByThread, 0)
    }

    // MARK: - React Native fatal

    func test_rnFatal_keepsThePrefix_withoutRepeatingTheDescription() {
        var report = FakeReport.nsException()
        report.exceptionName = "RCTFatalException: Unhandled JS Exception: TypeError: undefined is not a function"
        report.exceptionReason = "Unhandled JS Exception: TypeError: undefined is not a function"

        let crash = CrashReportMapper.map(report)

        XCTAssertEqual(crash.kind, .rnFatal)
        XCTAssertEqual(crash.errorType, "SIGABRT")
        XCTAssertEqual(crash.errorMessage, "RCTFatalException: Unhandled JS Exception: TypeError: undefined is not a function")
    }

    // MARK: - Bare signal

    func test_bareSignal_namesTheSignalAndItsCode_andSendsOnlyTheCrashedThread_uncapped() throws {
        let crash = CrashReportMapper.map(FakeReport())
        let threads = try decodedThreads(crash)

        XCTAssertEqual(crash.kind, .signal)
        XCTAssertEqual(crash.exceptionType, "SIGSEGV")
        XCTAssertEqual(crash.errorType, "SIGSEGV")
        XCTAssertEqual(crash.errorMessage, "SIGSEGV (SEGV_MAPERR)")
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].count, 250, "a signal crash keeps every frame of its thread")
        XCTAssertEqual(threads[0].first?[Keys.binary.rawValue], "HostApp")
        XCTAssertEqual(crash.triggeredByThread, 0)
    }

    func test_bareSignal_withACodeAndroidDoesNotName_isTheSignalAlone() {
        var report = FakeReport()
        report.signalName = "SIGABRT"
        report.signalCode = "#0"
        XCTAssertEqual(CrashReportMapper.map(report).errorMessage, "SIGABRT")

        report.signalName = "SIGSEGV"
        report.signalCode = "SEGV_NOOP"
        XCTAssertEqual(CrashReportMapper.map(report).errorMessage, "SIGSEGV")

        report.signalCode = nil
        XCTAssertEqual(CrashReportMapper.map(report).errorMessage, "SIGSEGV")
    }

    func test_signalCodes_matchAndroidsNames() {
        let named: [(String, String)] = [
            ("SIGSEGV", "SEGV_MAPERR"), ("SIGSEGV", "SEGV_ACCERR"),
            ("SIGBUS", "BUS_ADRALN"), ("SIGBUS", "BUS_ADRERR"), ("SIGBUS", "BUS_OBJERR"),
            ("SIGILL", "ILL_ILLOPC"), ("SIGILL", "ILL_ILLTRP"), ("SIGILL", "ILL_BADSTK"),
            ("SIGFPE", "FPE_INTDIV"), ("SIGFPE", "FPE_FLTINV"),
            ("SIGTRAP", "TRAP_BRKPT"), ("SIGTRAP", "TRAP_TRACE")
        ]
        for (signal, code) in named {
            XCTAssertEqual(CrashReportMapper.signalCode(signal, code), code, "\(signal) \(code)")
        }
        // Darwin's numbers for a signal sent by software, which PLCrashReporter cannot name.
        XCTAssertEqual(CrashReportMapper.signalCode("SIGABRT", "#65537"), "SI_USER")
        XCTAssertEqual(CrashReportMapper.signalCode("SIGABRT", "#65538"), "SI_QUEUE")
        XCTAssertNil(CrashReportMapper.signalCode("SIGSEGV", "BUS_ADRALN"), "a code belongs to its own signal")
    }

    // MARK: - Message cap

    func test_message_isCappedAt102UTF16Units_nameIncluded() {
        let name = "NSInvalidArgumentException"
        let exact = String(repeating: "a", count: 102 - name.count - 2)
        XCTAssertEqual(CrashReportMapper.map(FakeReport.nsException(reason: exact)).errorMessage.utf16.count, 102)

        let crash = CrashReportMapper.map(FakeReport.nsException(reason: exact + "b"))
        XCTAssertEqual(crash.errorMessage.utf16.count, 102)
        XCTAssertEqual(crash.errorMessage, "\(name): \(exact)")
    }

    func test_messageCap_neverSplitsASurrogatePair() {
        let straddling = String(repeating: "a", count: 101) + "😀"
        let capped = CrashReportMapper.capped(straddling)
        XCTAssertEqual(capped, String(repeating: "a", count: 101))

        let fitting = String(repeating: "a", count: 100) + "😀"
        XCTAssertEqual(CrashReportMapper.capped(fitting), fitting)
    }

    // MARK: - Wire shape

    func test_errorContext_crashBranch_sendsTheTypeAndMessage() {
        let span = MockSpanData(attributes: [
            Keys.isCrash.rawValue: AttributeValue.bool(true),
            Keys.exceptionType.rawValue: AttributeValue("SIGABRT"),
            Keys.errorType.rawValue: AttributeValue("SIGABRT"),
            Keys.errorMessage.rawValue: AttributeValue("NSInvalidArgumentException: boom"),
            Keys.threads.rawValue: AttributeValue("[]"),
            Keys.baseAddress.rawValue: AttributeValue("0x100000000"),
            Keys.arch.rawValue: AttributeValue("arm64")
        ])

        let context = ErrorContext(otel: span).getDictionary()

        XCTAssertEqual(context[Keys.exceptionType.rawValue] as? String, "SIGABRT")
        XCTAssertEqual(context[Keys.errorType.rawValue] as? String, "SIGABRT")
        XCTAssertEqual(context[Keys.errorMessage.rawValue] as? String, "NSInvalidArgumentException: boom")
        XCTAssertEqual(context[Keys.baseAddress.rawValue] as? String, "0x100000000")
        XCTAssertEqual(context[Keys.isCrash.rawValue] as? Bool, true)
    }

    func test_errorContext_crashWithoutMessage_fallsBackToTheSignal() {
        let span = MockSpanData(attributes: [
            Keys.isCrash.rawValue: AttributeValue.bool(true),
            Keys.exceptionType.rawValue: AttributeValue("SIGSEGV")
        ])

        let context = ErrorContext(otel: span).getDictionary()

        XCTAssertEqual(context[Keys.errorMessage.rawValue] as? String, "SIGSEGV")
        XCTAssertEqual(context[Keys.errorType.rawValue] as? String, "SIGSEGV")
    }

    func test_errorContext_errorWithThreads_isNotACrash() {
        let threads = Helper.convertArrayOfStringToJsonString(array: [
            Helper.convertArrayToJsonString(array: [[Keys.binary.rawValue: "HostApp"]])
        ])
        let span = MockSpanData(attributes: [
            Keys.errorMessage.rawValue: AttributeValue("Application Not Responding"),
            Keys.errorType.rawValue: AttributeValue("anr"),
            Keys.threads.rawValue: AttributeValue(threads),
            Keys.isCrash.rawValue: AttributeValue.bool(false)
        ])

        let context = ErrorContext(otel: span).getDictionary()

        XCTAssertEqual(context[Keys.isCrash.rawValue] as? Bool, false)
        XCTAssertEqual(context[Keys.errorMessage.rawValue] as? String, "Application Not Responding")
        XCTAssertEqual((context[Keys.threads.rawValue] as? [[[String: Any]]])?.first?.first?[Keys.binary.rawValue] as? String, "HostApp")
    }

    func test_errorContext_hybridCrash_keepsItsShape() {
        let stackTrace = Helper.convertArrayToJsonString(array: [["fileName": "index.bundle", "lineNumber": 12]])
        let span = MockSpanData(attributes: [
            Keys.domain.rawValue: AttributeValue(""),
            Keys.errorMessage.rawValue: AttributeValue("undefined is not a function"),
            Keys.errorType.rawValue: AttributeValue("TypeError"),
            Keys.stackTrace.rawValue: AttributeValue(stackTrace),
            Keys.isCrash.rawValue: AttributeValue.bool(true)
        ])

        let context = ErrorContext(otel: span).getDictionary()

        XCTAssertEqual(Set(context.keys), [Keys.errorMessage.rawValue, Keys.errorType.rawValue,
                                           Keys.originalStackTrace.rawValue, Keys.isCrash.rawValue])
        XCTAssertEqual(context[Keys.errorMessage.rawValue] as? String, "undefined is not a function")
        XCTAssertEqual(context[Keys.errorType.rawValue] as? String, "TypeError")
        XCTAssertEqual(context[Keys.isCrash.rawValue] as? Bool, true)
    }
}

// MARK: - ignoreErrors

final class IgnoreErrorsMatchingTests: XCTestCase {

    private var rum: CoralogixRum?

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        try super.tearDownWithError()
    }

    private func exporter(ignoring patterns: [String]) throws -> CoralogixExporter {
        let sdk = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: [], ignoreErrors: patterns))
        rum = sdk
        return try XCTUnwrap(sdk.coralogixExporter)
    }

    private func error(_ message: String, type: String? = nil) -> SpanDataProtocol {
        var attributes: [String: Any] = [Keys.errorMessage.rawValue: AttributeValue(message)]
        if let type { attributes[Keys.errorType.rawValue] = AttributeValue(type) }
        return MockSpanData(attributes: attributes)
    }

    private func keeps(_ span: SpanDataProtocol, ignoring patterns: [String]) throws -> Bool {
        try exporter(ignoring: patterns).shouldFilterIgnoreError(span: span)
    }

    func test_aLaterPatternIsTried() throws {
        XCTAssertFalse(try keeps(error("Network timeout"), ignoring: ["foo", "timeout"]))
    }

    func test_anInvalidPatternIsSkipped() throws {
        XCTAssertFalse(try keeps(error("Network timeout"), ignoring: ["(", "timeout"]))
    }

    func test_theErrorTypeIsMatched() throws {
        XCTAssertFalse(try keeps(error("x is undefined", type: "TypeError"), ignoring: ["TypeError"]))
    }

    func test_aSignalPattern_stillDropsAnExceptionCrash() throws {
        let crash = CrashReportMapper.map(FakeReport.nsException())
        XCTAssertFalse(try keeps(error(crash.errorMessage, type: crash.errorType), ignoring: ["SIGABRT"]))
    }

    func test_theExceptionName_dropsTheCrash_inAnyCase() throws {
        let crash = CrashReportMapper.map(FakeReport.nsException())
        let span = error(crash.errorMessage, type: crash.errorType)
        XCTAssertFalse(try keeps(span, ignoring: ["NSInvalidArgumentException"]))
        XCTAssertFalse(try keeps(span, ignoring: ["nsinvalidargumentexception"]))
    }

    func test_substringMatching_isUnchanged() throws {
        XCTAssertFalse(try keeps(error("Network timeout"), ignoring: ["timeout"]))
        XCTAssertTrue(try keeps(error("Network timeout"), ignoring: ["foo"]))
    }

    func test_textCutByTheCap_isNotMatched() throws {
        let reason = String(repeating: "x", count: 200) + " needle " + String(repeating: "y", count: 92)
        let crash = CrashReportMapper.map(FakeReport.nsException(reason: reason))
        XCTAssertTrue(try keeps(error(crash.errorMessage, type: crash.errorType), ignoring: ["needle"]))
    }
}

// MARK: - A recovered crash on the wire

final class RecoveredCrashWireTests: XCTestCase {

    private var rum: CoralogixRum?

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        try super.tearDownWithError()
    }

    private final class RecordingUploader: SpanUploading {
        private let lock = NSLock()
        private var _events: [[String: Any]] = []
        var events: [[String: Any]] {
            lock.lock(); defer { lock.unlock() }
            return _events
        }

        func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
            lock.lock(); defer { lock.unlock() }
            _events.append(contentsOf: spans)
            return .delivered
        }
    }

    private func errorContexts(_ events: [[String: Any]]) -> [[String: Any]] {
        events.compactMap { event in
            let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
            return cxRum?[Keys.errorContext.rawValue] as? [String: Any]
        }
    }

    private func emit(_ crash: MappedCrash, ignoring patterns: [String] = []) throws -> (RecordingUploader, CoralogixExporter) {
        let sdk = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: [], ignoreErrors: patterns))
        rum = sdk
        let exporter = try XCTUnwrap(sdk.coralogixExporter)
        let uploader = RecordingUploader()
        exporter.spanUploader = uploader

        sdk.emitRecoveredCrash(crash)
        let flushed = expectation(description: "flushed")
        sdk.flush { flushed.fulfill() }
        wait(for: [flushed], timeout: 10)
        return (uploader, exporter)
    }

    func test_recoveredException_reachesTheWireSignalShaped() throws {
        let crash = CrashReportMapper.map(FakeReport.nsException())
        let (uploader, _) = try emit(crash)

        let context = try XCTUnwrap(errorContexts(uploader.events).first { $0[Keys.isCrash.rawValue] as? Bool == true })
        XCTAssertEqual(context[Keys.exceptionType.rawValue] as? String, "SIGABRT")
        XCTAssertEqual(context[Keys.errorType.rawValue] as? String, "SIGABRT")
        XCTAssertEqual(context[Keys.errorMessage.rawValue] as? String, crash.errorMessage)
        XCTAssertEqual(context[Keys.triggeredByThread.rawValue] as? Int, 0)
        XCTAssertEqual((context[Keys.threads.rawValue] as? [Any])?.count, 3)
        XCTAssertEqual(context[Keys.baseAddress.rawValue] as? String, "0x100000000")
    }

    func test_recoveredCrash_droppedByIgnoreErrors_isPolicyDropped() throws {
        let crash = CrashReportMapper.map(FakeReport.nsException())
        let (uploader, exporter) = try emit(crash, ignoring: ["NSInvalidArgumentException"])

        XCTAssertFalse(errorContexts(uploader.events).contains { $0[Keys.isCrash.rawValue] as? Bool == true })
        XCTAssertEqual(exporter.crashUploadOutcome(id: crash.crashId), .policyDropped)
    }
}
