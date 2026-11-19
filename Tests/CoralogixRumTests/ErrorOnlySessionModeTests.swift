//
//  ErrorOnlySessionModeTests.swift
//
//  How a session's mode (full, held until an error, dropped) is decided and carried: the options
//  and their resolver, the per-span stamp, the crash context and stored crash records, the
//  traceparent flag, and the two `session_context` fields on the wire.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class ErrorOnlySessionModeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
    }

    // MARK: - Config resolver

    func testMaxRumEvents_resolvesInvalidAndOutOfRangeValues() {
        XCTAssertEqual(SessionWithErrorConfig().maxRumEvents, 5_000, "omitted → default")
        XCTAssertEqual(SessionWithErrorConfig(maxRumEvents: 0).maxRumEvents, 5_000)
        XCTAssertEqual(SessionWithErrorConfig(maxRumEvents: -10).maxRumEvents, 5_000)
        XCTAssertEqual(SessionWithErrorConfig(maxRumEvents: 50_000).maxRumEvents, 20_000)
        XCTAssertEqual(SessionWithErrorConfig(maxRumEvents: 1_234).maxRumEvents, 1_234)
    }

    func testOptions_defaultToOff() {
        let options = makeErrorOnlyOptions(sampleRate: 100)
        XCTAssertFalse(options.alwaysTrackSessionsWithErrors)
        XCTAssertFalse(options.onlyWithErrorConfig.enable)
        XCTAssertEqual(options.onlyWithErrorConfig.maxRumEvents, 5_000)
        XCTAssertEqual(options.onlyWithErrorConfig.instrumentationsToSend, [])
    }

    func testSessionMode_truthTable() {
        let enable = SessionWithErrorConfig(enable: true)
        XCTAssertEqual(makeErrorOnlyOptions(sampleRate: 100).sessionMode(sampledIn: true), .full)
        XCTAssertEqual(makeErrorOnlyOptions(sampleRate: 100, alwaysTrack: true).sessionMode(sampledIn: true), .full)
        XCTAssertEqual(makeErrorOnlyOptions(sampleRate: 100, config: enable).sessionMode(sampledIn: true), .errorOnly)
        XCTAssertEqual(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true).sessionMode(sampledIn: false), .errorOnly)
        XCTAssertEqual(makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true, config: enable).sessionMode(sampledIn: false), .errorOnly)
        XCTAssertEqual(makeErrorOnlyOptions(sampleRate: 0).sessionMode(sampledIn: false), .dropped)
        XCTAssertEqual(makeErrorOnlyOptions(sampleRate: 0, config: enable).sessionMode(sampledIn: false), .dropped)
    }

    func testInitPayload_reportsTheNewOptions() throws {
        let options = makeErrorOnlyOptions(sampleRate: 20, alwaysTrack: true,
                                  config: SessionWithErrorConfig(enable: true, maxRumEvents: 700,
                                                                 instrumentationsToSend: [.mobileVitals, .errors]))
        let initData = options.getInitData()
        XCTAssertEqual(initData[Keys.alwaysTrackSessionsWithErrors.rawValue] as? Bool, true)
        let config = try XCTUnwrap(initData[Keys.onlyWithErrorConfig.rawValue] as? [String: Any])
        XCTAssertEqual(config[Keys.enable.rawValue] as? Bool, true)
        XCTAssertEqual(config[Keys.maxRumEvents.rawValue] as? Int, 700)
        XCTAssertEqual(config[Keys.instrumentationsToSend.rawValue] as? [String], ["errors", "mobileVitals"])
    }

    // MARK: - Session stamp

    func testStamp_followsThePolicyAtSeedAndOnRotation() throws {
        var stamps: [SessionManager.CrashStamp] = []
        let manager = SessionManager(snapshotStore: SessionSnapshotStore(directory: temporaryDirectory()),
                                     crashStampObserver: { stamps.append($0) })
        let options = makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true)
        manager.setErrorOnlyPolicy { options.sessionMode(sampledIn: $0) == .errorOnly }

        manager.setSessionSampledIn(false)
        XCTAssertTrue(manager.isSessionErrorOnly)
        XCTAssertEqual(stampValue(manager, .spanSessionOnlyWithErrorMode), "true")
        XCTAssertEqual(stamps.last?.errorOnly, true, "The crash context must carry the mode next to the sampling flag.")

        manager.samplingRoller = { true }
        manager.setupSessionMetadata()
        XCTAssertFalse(manager.isSessionErrorOnly, "A sampled-in session without enable is full.")
        XCTAssertEqual(stampValue(manager, .spanSessionOnlyWithErrorMode), "false")
        XCTAssertEqual(stamps.last?.errorOnly, false)
        XCTAssertEqual(manager.liveSessionSampling()?.errorOnly, false)
    }

    // MARK: - Crash context and records

    func testCrashContextEnvelope_decodesTheMode_andToleratesItsAbsence() throws {
        func envelope(_ session: [String: Any]) throws -> CrashContextEnvelope? {
            let json: [String: Any] = [Keys.crashContextVersion.rawValue: 1, Keys.crashContextSession.rawValue: session]
            return CrashContextEnvelope(data: try JSONSerialization.data(withJSONObject: json))
        }
        let withMode = try envelope([Keys.sessionId.rawValue: "s1",
                                     Keys.spanSessionSampledIn.rawValue: false,
                                     Keys.spanSessionOnlyWithErrorMode.rawValue: true])
        XCTAssertEqual(withMode?.session?.errorOnly, true)
        XCTAssertEqual(withMode?.session?.sampledIn, false)

        let older = try envelope([Keys.sessionId.rawValue: "s1", Keys.spanSessionSampledIn.rawValue: false])
        XCTAssertEqual(older?.session?.id, "s1")
        XCTAssertNil(older?.session?.errorOnly)
    }

    func testStoredCrashRecord_olderFileWithoutTheMode_stillDecodes() throws {
        let session = StoredCrashRecord.Session(id: "s1", creationDate: 10, sampledIn: false, errorOnly: true)
        let roundTrip = try JSONDecoder().decode(StoredCrashRecord.Session.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(roundTrip.errorOnly, true)

        let older = Data(#"{"id":"s1","creationDate":10,"sampledIn":false}"#.utf8)
        let decoded = try JSONDecoder().decode(StoredCrashRecord.Session.self, from: older)
        XCTAssertEqual(decoded.id, "s1")
        XCTAssertNil(decoded.errorOnly)
    }

    func testRecoveredCrash_isStampedWithTheCrashedSessionsMode() throws {
        let rum = CoralogixRum(options: makeErrorOnlyOptions(sampleRate: 100))
        defer { rum.shutdown() }
        let span = rum.makeSpan(event: .error, source: .console, severity: .error)
        let record = StoredCrashRecord(crashId: "c1", kind: .native, crashTime: Date(), failedUploads: 0,
                                       session: .init(id: "crashed", creationDate: 10, sampledIn: false, errorOnly: true),
                                       counters: .empty(sessionId: "crashed"))
        rum.attribute(span, to: record)
        let attributes = try XCTUnwrap((span as? any ReadableSpan)?.toSpanData().attributes)
        XCTAssertEqual(attributes[Keys.spanSessionOnlyWithErrorMode.rawValue]?.description, "true")
        XCTAssertEqual(attributes[Keys.spanSessionSampledIn.rawValue]?.description, "false")
    }

    // MARK: - traceparent

    func testSampler_errorOnlySession_isSampled_droppedIsNot() {
        let sampler = CxCustomSampler(excludeFromSampling: [])
        func decision(errorOnly: Bool) -> Bool {
            let attributes: [String: AttributeValue] = [
                Keys.eventType.rawValue: .string(CoralogixEventType.networkRequest.rawValue),
                Keys.spanSessionSampledIn.rawValue: .string("false"),
                Keys.spanSessionOnlyWithErrorMode.rawValue: .string(String(errorOnly))
            ]
            return sampler.shouldSample(parentContext: nil, traceId: TraceId.random(), name: "n", kind: .client,
                                        attributes: attributes, parentLinks: []).isSampled
        }
        XCTAssertTrue(decision(errorOnly: true), "An error-only session sends 01.")
        XCTAssertFalse(decision(errorOnly: false), "A dropped session still sends 00.")
    }

    func testNetworkRequestSampling_errorOnlySession_isSampled() throws {
        let rum = CoralogixRum(options: makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true))
        defer { rum.shutdown() }
        XCTAssertTrue(rum.networkRequestSampling().isSampled)

        let dropped = CoralogixRum(options: makeErrorOnlyOptions(sampleRate: 0))
        defer { dropped.shutdown() }
        XCTAssertFalse(dropped.networkRequestSampling().isSampled)
    }

    func testInstall_errorOnlySession_installsWhatASampledInSessionDoes() {
        let options = makeErrorOnlyOptions(sampleRate: 0, alwaysTrack: true)
        let reports = options.sessionMode(sampledIn: false).reports
        XCTAssertTrue(CoralogixRum.shouldInstall(.errors, options: options, sampledIn: reports),
                      "Crash capture must be installed in an error-only session.")
        XCTAssertTrue(CoralogixRum.shouldInstall(.mobileVitals, options: options, sampledIn: reports))
        XCTAssertFalse(CoralogixRum.shouldInstall(.errors, options: makeErrorOnlyOptions(sampleRate: 0),
                                                  sampledIn: makeErrorOnlyOptions(sampleRate: 0).sessionMode(sampledIn: false).reports))
    }

    // MARK: - Wire fields

    func testFullSession_sendsOnlyWithErrorModeFalse_andBeforeSendCannotForgeEitherField() throws {
        let options = makeErrorOnlyOptions(sampleRate: 100, beforeSend: { cxRum in
            var edited = cxRum
            var session = edited[Keys.sessionContext.rawValue] as? [String: Any] ?? [:]
            session[Keys.onlyWithErrorMode.rawValue] = true
            session[Keys.hasError.rawValue] = true
            edited[Keys.sessionContext.rawValue] = session
            return edited
        })
        let rum = CoralogixRum(options: options)
        defer { rum.shutdown() }
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = CapturingSpanUploader()
        exporter.spanUploader = uploader

        _ = exporter.export(spans: [makeSamplingSpan(eventType: .log,
                                                     extraAttributes: [Keys.spanSessionOnlyWithErrorMode.rawValue: .string("false")])],
                            explicitTimeout: nil)

        let session = try XCTUnwrap(uploader.cxRumPayloads().last?[Keys.sessionContext.rawValue] as? [String: Any])
        XCTAssertEqual(session[Keys.onlyWithErrorMode.rawValue] as? Bool, false, "Restored after beforeSend.")
        XCTAssertNil(session[Keys.hasError.rawValue], "hasError is SDK-owned; a forged one must not survive.")
    }

    // MARK: - Helpers

    private func stampValue(_ manager: SessionManager, _ key: Keys) -> String? {
        manager.sessionSpanAttributes().first { $0.key == key.rawValue }?.value
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ErrorOnlyMode-\(UUID().uuidString)")
    }
}

func makeErrorOnlyOptions(sampleRate: Int,
                 alwaysTrack: Bool = false,
                 config: SessionWithErrorConfig? = nil,
                 exclude: Set<ExcludableInstrumentation> = [],
                 ignoreErrors: [String]? = nil,
                 beforeSend: (([String: Any]) -> [String: Any]?)? = nil,
                 tracesExporter: TracesExporterCallback? = nil) -> CoralogixExporterOptions {
    CoralogixExporterOptions(coralogixDomain: .US2,
                             environment: "test",
                             application: "TestApp",
                             version: "1.0.0",
                             publicKey: "test-key",
                             ignoreErrors: ignoreErrors,
                             sessionSampleRate: sampleRate,
                             excludeFromSampling: exclude,
                             alwaysTrackSessionsWithErrors: alwaysTrack,
                             onlyWithErrorConfig: config,
                             beforeSend: beforeSend,
                             tracesExporter: tracesExporter)
}
