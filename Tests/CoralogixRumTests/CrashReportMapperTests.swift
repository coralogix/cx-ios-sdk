//
//  CrashReportMapperTests.swift
//
//  The mapper turns a crash report into the values the crash span carries. Fakes pin the
//  rules; a live PLCrashReporter report checks the adapter reads a real one. A recovered crash
//  starts a trace of its own, while a live error keeps following the global span.
//

import XCTest
import CrashReporter
import CoralogixInternal

@testable import Coralogix

final class CrashReportMapperTests: XCTestCase {

    private struct FakeReport: CrashReportReading {
        var reportId: String? = "8F7E6D5C-4B3A-4291-8070-6F5E4D3C2B1A"
        var timestamp: Date? = Date(timeIntervalSince1970: 1_700_000_000)
        var signalName = "SIGSEGV"
        var signalCode: String? = "SEGV_MAPERR"
        var exceptionName: String?
        var exceptionReason: String?
        var processName: String? = "HostApp"
        var processID: UInt = 4242
        var applicationIdentifier: String? = "com.example.host"
        var threads: [CrashThread] = [
            CrashThread(number: 0, crashed: false, frames: [
                CrashStackFrame(frameNumber: "0", binary: "libsystem_kernel.dylib",
                                functionAddressCalled: "0x0000000100000010", base: "mach_msg", offset: "8")
            ]),
            CrashThread(number: 3, crashed: true, frames: [
                CrashStackFrame(frameNumber: "0", binary: "HostApp",
                                functionAddressCalled: "0x0000000100004000", base: "0x100000000", offset: "16384")
            ])
        ]
        var mainBinaryImage: (baseAddress: String, arch: String)? = ("0x100000000", "arm64")
    }

    // MARK: - Mapping

    func test_map_carriesTheReportValues() throws {
        let mapped = CrashReportMapper.map(FakeReport())

        XCTAssertEqual(mapped.crashId, "8F7E6D5C-4B3A-4291-8070-6F5E4D3C2B1A")
        XCTAssertEqual(mapped.crashTime, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(mapped.exceptionType, "SIGSEGV")
        XCTAssertEqual(mapped.processName, "HostApp")
        XCTAssertEqual(mapped.applicationIdentifier, "com.example.host")
        XCTAssertEqual(mapped.pid, 4242)
        XCTAssertEqual(mapped.triggeredByThread, 0, "the crashed thread is sent first")
        XCTAssertEqual(mapped.baseAddress, "0x100000000")
        XCTAssertEqual(mapped.arch, "arm64")
    }

    func test_map_signalCrash_encodesOnlyTheCrashedThread_withItsFrames() throws {
        let mapped = CrashReportMapper.map(FakeReport())

        let threads = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(mapped.threadsJSON.utf8)) as? [String])
        XCTAssertEqual(threads.count, 1)
        let crashedFrames = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(threads[0].utf8)) as? [[String: String]])
        XCTAssertEqual(crashedFrames.first?[Keys.binary.rawValue], "HostApp")
        XCTAssertEqual(crashedFrames.first?[Keys.functionAddressCalled.rawValue], "0x0000000100004000")
        XCTAssertEqual(crashedFrames.first?[Keys.offset.rawValue], "16384")
    }

    func test_map_withoutABinaryImage_leavesBaseAddressAndArchOut() {
        var report = FakeReport()
        report.mainBinaryImage = nil
        let mapped = CrashReportMapper.map(report)
        XCTAssertNil(mapped.baseAddress)
        XCTAssertNil(mapped.arch)
    }

    // MARK: - Crash id

    func test_crashId_isTheSameEveryTimeTheReportIsRead() {
        XCTAssertEqual(CrashReportMapper.map(FakeReport()).crashId, CrashReportMapper.map(FakeReport()).crashId)
    }

    func test_crashId_withoutAReportUUID_isDerivedFromTheCrash_andStable() {
        var report = FakeReport()
        report.reportId = nil
        let first = CrashReportMapper.crashId(for: report)
        XCTAssertEqual(first, "plcr-1700000000000-4242-SIGSEGV")
        XCTAssertEqual(first, CrashReportMapper.crashId(for: report))

        report.timestamp = Date(timeIntervalSince1970: 1_700_000_001)
        XCTAssertNotEqual(CrashReportMapper.crashId(for: report), first, "a different crash gets a different id")
    }

    // MARK: - Real PLCrashReporter report

    func test_liveReport_isReadThroughTheAdapter_withAStableId() throws {
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: [])
        let reporter = try XCTUnwrap(PLCrashReporter(configuration: config))
        let data = try reporter.generateLiveReportAndReturnError()
        let report = try PLCrashReport(data: data)

        let first = CrashReportMapper.map(PLCrashReportReader(report: report))
        let second = CrashReportMapper.map(PLCrashReportReader(report: try PLCrashReport(data: data)))

        XCTAssertFalse(first.crashId.isEmpty)
        XCTAssertEqual(first.crashId, second.crashId, "the same report gives the same id on every read")
        XCTAssertNotNil(UUID(uuidString: first.crashId), "a PLCrashReporter report carries a UUID")
        XCTAssertEqual(first.pid, UInt(ProcessInfo.processInfo.processIdentifier))
        let threads = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(first.threadsJSON.utf8)) as? [String])
        XCTAssertFalse(threads.isEmpty, "a live report has at least the calling thread")
    }
}

// MARK: - Trace of a recovered crash

final class RecoveredCrashTraceTests: XCTestCase {

    private var rum: CoralogixRum?

    override func tearDownWithError() throws {
        CoralogixCustomGlobalSpanRegistry.shared.teardownIfNeeded()
        rum?.shutdown()
        rum = nil
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        try super.tearDownWithError()
    }

    private func startGlobalSpan() throws -> (CoralogixRum, CoralogixGlobalSpan, SpanData) {
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        let sdk = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: [],
                                                            traceParentInHeader: [Keys.enable.rawValue: true]))
        rum = sdk
        let tracer = try XCTUnwrap(sdk.getCustomTracer())
        let global = try XCTUnwrap(tracer.startGlobalSpan(name: "checkout"))
        let globalData = try XCTUnwrap(global.span as? any ReadableSpan).toSpanData()
        return (sdk, global, globalData)
    }

    func test_recoveredCrash_startsATraceOfItsOwn_evenWithAGlobalSpan() throws {
        let (sdk, global, globalData) = try startGlobalSpan()
        defer { global.endSpan() }

        let span = sdk.makeSpan(event: .error, source: .console, severity: .error, startsNewTrace: true)
        defer { span.end() }
        let data = try XCTUnwrap(span as? any ReadableSpan).toSpanData()

        XCTAssertNil(data.parentSpanId, "a recovered crash has no parent")
        XCTAssertNotEqual(data.traceId, globalData.traceId)
    }

    func test_liveError_stillParentsToTheGlobalSpan() throws {
        let (sdk, global, globalData) = try startGlobalSpan()
        defer { global.endSpan() }

        let span = sdk.makeSpan(event: .error, source: .console, severity: .error)
        defer { span.end() }
        let data = try XCTUnwrap(span as? any ReadableSpan).toSpanData()

        XCTAssertEqual(data.parentSpanId, globalData.spanId)
        XCTAssertEqual(data.traceId, globalData.traceId)
    }
}
