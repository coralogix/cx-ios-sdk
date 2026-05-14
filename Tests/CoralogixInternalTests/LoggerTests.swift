//
//  LoggerTests.swift
//  CoralogixInternal
//

import XCTest
@testable import CoralogixInternal

final class LoggerTests: XCTestCase {

    // MARK: - Test doubles

    final class RecordingLogger: Logger {
        struct Entry {
            let level: LogLevel
            let message: String
            let metadataKeys: [String]
            let file: String
            let function: String
            let line: Int
        }
        private(set) var entries: [Entry] = []
        private(set) var evaluations = 0

        func log(level: LogLevel,
                 message: @autoclosure () -> String,
                 metadata: [String: Any]?,
                 file: String,
                 function: String,
                 line: Int) {
            evaluations += 1
            entries.append(Entry(
                level: level,
                message: message(),
                metadataKeys: metadata?.keys.sorted() ?? [],
                file: file,
                function: function,
                line: line
            ))
        }
    }

    final class LevelFilteringLogger: Logger {
        let threshold: LogLevel
        private(set) var emitted: [String] = []
        private(set) var evaluations = 0

        init(threshold: LogLevel) { self.threshold = threshold }

        func log(level: LogLevel,
                 message: @autoclosure () -> String,
                 metadata: [String: Any]?,
                 file: String,
                 function: String,
                 line: Int) {
            guard level >= threshold else { return }
            evaluations += 1
            emitted.append(message())
        }
    }

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        Log.isDebug = false
        Log.shared = OSLogger()
    }

    override func tearDown() {
        Log.isDebug = false
        Log.shared = OSLogger()
        super.tearDown()
    }

    // MARK: - LogLevel

    func test_LogLevel_isOrderedByRawValue() {
        XCTAssertLessThan(LogLevel.trace, LogLevel.debug)
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.info, LogLevel.warning)
        XCTAssertLessThan(LogLevel.warning, LogLevel.error)
        XCTAssertLessThan(LogLevel.error, LogLevel.critical)
    }

    // MARK: - Logger protocol

    func test_protocolLog_forwardsLevelMessageAndMetadata() {
        let logger = RecordingLogger()
        logger.log(level: .info,
                   message: "hi",
                   metadata: ["k": 1, "v": "x"],
                   file: "F.swift",
                   function: "fn()",
                   line: 42)

        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries[0].level, .info)
        XCTAssertEqual(logger.entries[0].message, "hi")
        XCTAssertEqual(logger.entries[0].metadataKeys, ["k", "v"])
        XCTAssertEqual(logger.entries[0].file, "F.swift")
        XCTAssertEqual(logger.entries[0].function, "fn()")
        XCTAssertEqual(logger.entries[0].line, 42)
    }

    func test_protocolExtension_appliesDefaultsForMetadataAndCaller() {
        let logger = RecordingLogger()
        logger.log(level: .warning, "danger")

        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries[0].level, .warning)
        XCTAssertEqual(logger.entries[0].message, "danger")
        XCTAssertEqual(logger.entries[0].metadataKeys, [])
        XCTAssertFalse(logger.entries[0].file.isEmpty)
        XCTAssertFalse(logger.entries[0].function.isEmpty)
        XCTAssertGreaterThan(logger.entries[0].line, 0)
    }

    func test_disabledLevel_doesNotEvaluateAutoclosure() {
        let logger = LevelFilteringLogger(threshold: .error)
        var sideEffect = 0
        func expensive() -> String {
            sideEffect += 1
            return "x"
        }

        logger.log(level: .debug,
                   message: expensive(),
                   metadata: nil,
                   file: #fileID,
                   function: #function,
                   line: #line)

        XCTAssertEqual(sideEffect, 0, "autoclosure must not be evaluated when level is filtered out")
        XCTAssertEqual(logger.evaluations, 0)
    }

    func test_enabledLevel_evaluatesAutoclosureExactlyOnce() {
        let logger = LevelFilteringLogger(threshold: .debug)
        var sideEffect = 0
        func expensive() -> String {
            sideEffect += 1
            return "x"
        }

        logger.log(level: .info,
                   message: expensive(),
                   metadata: nil,
                   file: #fileID,
                   function: #function,
                   line: #line)

        XCTAssertEqual(sideEffect, 1)
        XCTAssertEqual(logger.emitted, ["x"])
    }

    // MARK: - NoopLogger

    func test_noopLogger_doesNothing() {
        let noop = NoopLogger()
        noop.log(level: .critical,
                 message: "ignored",
                 metadata: ["k": 1],
                 file: #fileID,
                 function: #function,
                 line: #line)
        // No assertion beyond "doesn't crash" — NoopLogger has no observable state.
    }

    // MARK: - Log façade — isDebug gate

    func test_Log_d_doesNotEvaluateMessage_whenIsDebugIsFalse() {
        Log.isDebug = false
        let rec = RecordingLogger()
        Log.shared = rec

        var sideEffect = 0
        func expensive() -> String {
            sideEffect += 1
            return "should not be built"
        }

        Log.d(expensive())

        XCTAssertEqual(sideEffect, 0)
        XCTAssertEqual(rec.entries.count, 0)
    }

    func test_Log_d_routesToSharedLogger_atDebugLevel_whenIsDebugIsTrue() {
        Log.isDebug = true
        let rec = RecordingLogger()
        Log.shared = rec

        Log.d("hello")

        XCTAssertEqual(rec.entries.count, 1)
        XCTAssertEqual(rec.entries[0].level, .debug)
        XCTAssertEqual(rec.entries[0].message, "hello")
    }

    func test_Log_t_routesAtTraceLevel() {
        Log.isDebug = true
        let rec = RecordingLogger()
        Log.shared = rec

        Log.t("trace-me")

        XCTAssertEqual(rec.entries.first?.level, .trace)
        XCTAssertEqual(rec.entries.first?.message, "trace-me")
    }

    func test_Log_w_routesAtWarningLevel() {
        Log.isDebug = true
        let rec = RecordingLogger()
        Log.shared = rec

        Log.w("warn-me")

        XCTAssertEqual(rec.entries.first?.level, .warning)
        XCTAssertEqual(rec.entries.first?.message, "warn-me")
    }

    func test_Log_e_string_routesAtErrorLevel() {
        Log.isDebug = true
        let rec = RecordingLogger()
        Log.shared = rec

        Log.e("boom")

        XCTAssertEqual(rec.entries.first?.level, .error)
        XCTAssertEqual(rec.entries.first?.message, "boom")
    }

    func test_Log_e_stringWithError_combinesMessageAndLocalizedDescription() {
        Log.isDebug = true
        let rec = RecordingLogger()
        Log.shared = rec

        struct E: LocalizedError { var errorDescription: String? { "bad thing" } }
        Log.e("context", E())

        XCTAssertEqual(rec.entries.count, 1)
        XCTAssertEqual(rec.entries[0].level, .error)
        XCTAssertTrue(rec.entries[0].message.contains("context"))
        XCTAssertTrue(rec.entries[0].message.contains("bad thing"))
    }

    func test_Log_e_errorOnly_routesAtErrorLevel() {
        Log.isDebug = true
        let rec = RecordingLogger()
        Log.shared = rec

        struct E: LocalizedError { var errorDescription: String? { "only-error" } }
        Log.e(E())

        XCTAssertEqual(rec.entries.count, 1)
        XCTAssertEqual(rec.entries[0].level, .error)
        XCTAssertEqual(rec.entries[0].message, "only-error")
    }
}
