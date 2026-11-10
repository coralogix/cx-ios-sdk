//
//  CrashContextTests.swift
//
//  `CRXCrashContext` writes a small versioned JSON envelope into PLCrashReporter's custom data,
//  so every crash report carries the session it happened in. These tests read it back from a real
//  report. Custom data is process-wide, so each test puts back the sections it found.
//

import XCTest
import CrashReporter
import CoralogixInternal
#if canImport(CoralogixBootstrap)
import CoralogixBootstrap
#endif

@testable import Coralogix

final class CrashContextTests: XCTestCase {

    private var savedSections: [String: Any] = [:]
    private var savedReporter: PLCrashReporter?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedSections = CRXCrashContext.sections
        savedReporter = CRXCrashContext.activeReporter
        XCTAssertNotNil(savedReporter, "+load enabled a reporter in the test process and made it the active one")
    }

    override func tearDownWithError() throws {
        CRXCrashContext.activeReporter = savedReporter
        for name in CRXCrashContext.sections.keys where savedSections[name] == nil {
            CRXCrashContext.setSection(name, value: nil)
        }
        for (name, value) in savedSections {
            CRXCrashContext.setSection(name, value: value as? [String: Any])
        }
        try super.tearDownWithError()
    }

    private func liveReportContext() throws -> CrashContextEnvelope? {
        CrashContextEnvelope(data: try CrashContextTests.liveReport().customData)
    }

    /// A live report carrying the custom data our reporter holds. Generated on a reporter that
    /// does not symbolicate: the active one symbolicates every thread, which takes ~30 s per report.
    static func liveReport() throws -> PLCrashReport {
        let active = try XCTUnwrap(CRXCrashContext.activeReporter)
        let reporter = try XCTUnwrap(PLCrashReporter(configuration: PLCrashReporterConfig(signalHandlerType: .BSD,
                                                                                         symbolicationStrategy: [])))
        reporter.customData = active.customData
        return try PLCrashReport(data: ANRThreads.withLiveReportLock { try reporter.generateLiveReportAndReturnError() })
    }

    private let session: [String: Any] = [
        Keys.sessionId.rawValue: "c2a1f0de-0000-4000-8000-000000000001",
        Keys.crashContextSessionCreationTime.rawValue: 1_700_000_000_123,
        Keys.spanSessionSampledIn.rawValue: true
    ]

    // MARK: - Round trip

    func test_aSection_isCarriedByTheNextReport() throws {
        XCTAssertTrue(CRXCrashContext.setSection(Keys.crashContextSession.rawValue, value: session))

        let context = try XCTUnwrap(liveReportContext())
        XCTAssertEqual(context.session, .init(id: "c2a1f0de-0000-4000-8000-000000000001",
                                              creationTimeMillis: 1_700_000_000_123,
                                              sampledIn: true))
    }

    func test_reachesTheMapper_throughARealReport() throws {
        CRXCrashContext.setSection(Keys.crashContextSession.rawValue, value: session)
        let report = try Self.liveReport()

        let mapped = CrashReportMapper.map(PLCrashReportReader(report: report))

        XCTAssertEqual(mapped.context?.session?.id, "c2a1f0de-0000-4000-8000-000000000001")
    }

    func test_writingASecondSection_keepsTheFirst() throws {
        CRXCrashContext.setSection(Keys.crashContextSession.rawValue, value: session)
        CRXCrashContext.setSection(Keys.crashContextCxx.rawValue, value: [
            Keys.type.rawValue: "St13runtime_error",
            Keys.crashContextCxxWhat.rawValue: "boom"
        ])

        let context = try XCTUnwrap(liveReportContext())
        XCTAssertEqual(context.session?.id, "c2a1f0de-0000-4000-8000-000000000001")
        XCTAssertEqual(context.cxx, .init(type: "St13runtime_error", what: "boom"))
    }

    func test_removingASection_keepsTheOthers() throws {
        CRXCrashContext.setSection(Keys.crashContextSession.rawValue, value: session)
        CRXCrashContext.setSection(Keys.crashContextCxx.rawValue, value: [Keys.type.rawValue: "x"])
        CRXCrashContext.setSection(Keys.crashContextCxx.rawValue, value: nil)

        let context = try XCTUnwrap(liveReportContext())
        XCTAssertNotNil(context.session)
        XCTAssertNil(context.cxx)
    }

    // MARK: - Only through our own reporter

    func test_withoutAReporterOfOurs_nothingIsWritten_untilOneIsSet() throws {
        let ours = try XCTUnwrap(CRXCrashContext.activeReporter)
        CRXCrashContext.activeReporter = nil

        XCTAssertFalse(CRXCrashContext.setSection(Keys.crashContextSession.rawValue, value: session))

        CRXCrashContext.activeReporter = ours
        XCTAssertEqual(try liveReportContext()?.session?.id, "c2a1f0de-0000-4000-8000-000000000001",
                       "the held section is written as soon as our reporter is set")
    }

    func test_aReporterWeDidNotEnable_isNeverWrittenTo() throws {
        let other = try XCTUnwrap(PLCrashReporter(configuration: PLCrashReporterConfig(signalHandlerType: .BSD,
                                                                                      symbolicationStrategy: [])))

        CRXCrashContext.setSection(Keys.crashContextSession.rawValue, value: session)

        XCTAssertNil(other.customData)
        XCTAssertNotNil(CRXCrashContext.activeReporter?.customData)
    }

    // MARK: - Keys

    func test_objcAndSwiftKeys_agree() {
        let swiftKeys: Set<String> = [
            Keys.crashContextVersion, .crashContextSession, .sessionId, .crashContextSessionCreationTime,
            .spanSessionSampledIn, .crashContextCxx, .type, .crashContextCxxWhat
        ].reduce(into: []) { $0.insert($1.rawValue) }
        XCTAssertEqual(CRXCrashContext.allKeys, swiftKeys)
    }

    // MARK: - Decoding

    func test_decoding_isTolerant() {
        XCTAssertNil(CrashContextEnvelope(data: nil))
        XCTAssertNil(CrashContextEnvelope(data: Data("not json".utf8)))
        XCTAssertNil(CrashContextEnvelope(data: Data(#"{"v":2,"session":{"session_id":"a"}}"#.utf8)), "an unknown version is no context")
        XCTAssertNil(CrashContextEnvelope(data: Data(#"{"session":{"session_id":"a"}}"#.utf8)), "no version is no context")

        let noId = CrashContextEnvelope(data: Data(#"{"v":1,"session":{"is_session_sampled_in":true}}"#.utf8))
        XCTAssertNotNil(noId)
        XCTAssertNil(noId?.session, "a session without an id is no session")

        let seedOnly = CrashContextEnvelope(data: Data(#"{"v":1,"session":{"session_id":"seed"}}"#.utf8))
        XCTAssertEqual(seedOnly?.session, .init(id: "seed", creationTimeMillis: nil, sampledIn: nil))
    }
}
