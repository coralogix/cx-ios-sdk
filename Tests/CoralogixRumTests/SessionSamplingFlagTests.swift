//
//  SessionSamplingFlagTests.swift
//
//  CX-51128: the session sampling decision is stamped on every span at creation
//  (is_session_sampled_in) and surfaced as session_context.isSessionSampledIn on the
//  wire, in the otelSpan attribute mirror, and in the subset `beforeSend` receives —
//  so a callback can tell whether an event belongs to a sampled-in session or reached
//  export only via excludeFromSampling (e.g. keep just errors/ANRs at low sample rates).
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class SessionSamplingFlagTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
    }

    // MARK: - SessionManager stamps the decision alongside the session identity

    func testSessionSpanAttributes_containSampledOutStamp() {
        let sessionManager = SessionManager()
        sessionManager.setSessionSampledIn(false)

        let attrs = Dictionary(uniqueKeysWithValues: sessionManager.sessionSpanAttributes().map { ($0.key, $0.value) })

        XCTAssertEqual(attrs[Keys.spanSessionSampledIn.rawValue], "false")
        XCTAssertNotNil(attrs[Keys.sessionId.rawValue],
                        "The stamp must ride with the session identity attributes.")
    }

    func testSessionSpanAttributes_containSampledInStamp() {
        let sessionManager = SessionManager()
        sessionManager.setSessionSampledIn(true)

        let attrs = Dictionary(uniqueKeysWithValues: sessionManager.sessionSpanAttributes().map { ($0.key, $0.value) })

        XCTAssertEqual(attrs[Keys.spanSessionSampledIn.rawValue], "true")
    }

    // MARK: - Rotation re-rolls via the installed roller, atomically with the identity swap

    func testRotation_rerollsDecisionThroughSamplingRoller() {
        let sessionManager = SessionManager()
        sessionManager.setSessionSampledIn(true)
        sessionManager.samplingRoller = { false }

        sessionManager.setupSessionMetadata()

        XCTAssertFalse(sessionManager.isSessionSampledIn,
                       "Rotation must replace the decision with the roller's result.")
        let attrs = Dictionary(uniqueKeysWithValues: sessionManager.sessionSpanAttributes().map { ($0.key, $0.value) })
        XCTAssertEqual(attrs[Keys.spanSessionSampledIn.rawValue], "false")
    }

    func testRotation_withoutRoller_keepsSeededDecision() {
        // Sessions rotate before startup() installs the roller (e.g. the one created in
        // SessionManager.init); they must keep the seeded value, not flip to a default.
        let sessionManager = SessionManager()
        sessionManager.setSessionSampledIn(false)

        sessionManager.setupSessionMetadata()

        XCTAssertFalse(sessionManager.isSessionSampledIn)
    }

    // MARK: - End-to-end wiring through CoralogixRum init

    func testInit_sampledOutWithExclude_stampsFalseAndSyncsExporter() {
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 0, exclude: [.errors]))
        defer { rum.shutdown() }

        guard let sessionManager = rum.sessionManager else {
            return XCTFail("SessionManager must exist after init with a non-empty exclude set.")
        }
        XCTAssertFalse(sessionManager.isSessionSampledIn)
        let attrs = Dictionary(uniqueKeysWithValues: sessionManager.sessionSpanAttributes().map { ($0.key, $0.value) })
        XCTAssertEqual(attrs[Keys.spanSessionSampledIn.rawValue], "false")

        // Rotation must keep the exporter's filter flag and the stamp in agreement
        // (single roll per rotation — sampleRate 0 makes it deterministic).
        sessionManager.setupSessionMetadata()
        XCTAssertFalse(sessionManager.isSessionSampledIn)
        XCTAssertEqual(rum.coralogixExporter?.isCurrentSessionSampledIn(), false)
    }

    func testInit_sampledIn_stampsTrue() {
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        defer { rum.shutdown() }

        guard let sessionManager = rum.sessionManager else {
            return XCTFail("SessionManager must exist after a sampled-in init.")
        }
        XCTAssertTrue(sessionManager.isSessionSampledIn)
        let attrs = Dictionary(uniqueKeysWithValues: sessionManager.sessionSpanAttributes().map { ($0.key, $0.value) })
        XCTAssertEqual(attrs[Keys.spanSessionSampledIn.rawValue], "true")
    }

    // MARK: - Crash attribution: recovered crashes carry the crashed session's decision

    func testLastLaunchAttributes_carryCrashedSessionSamplingDecision() throws {
        let sessionManager = SessionManager()
        var metadata = try XCTUnwrap(sessionManager.sessionMetadata)
        metadata.oldSessionId = "crashed-session-abc"
        metadata.oldSessionTimeInterval = TimeInterval(1_600_000_000)
        metadata.oldSessionSampledIn = false
        sessionManager.sessionMetadata = metadata

        let attrs = Dictionary(uniqueKeysWithValues: sessionManager.lastLaunchSessionSpanAttributes())
        XCTAssertEqual(attrs[Keys.spanSessionSampledIn.rawValue], "false",
                       "A recovered crash must be stamped with the crashed session's decision, not the relaunch roll.")
        XCTAssertEqual(attrs[Keys.sessionId.rawValue], "crashed-session-abc")
    }

    func testLastLaunchAttributes_missingPersistedDecision_defaultsToSampledIn() throws {
        // Prior launch recorded by an SDK version that predates the persisted decision.
        let sessionManager = SessionManager()
        var metadata = try XCTUnwrap(sessionManager.sessionMetadata)
        metadata.oldSessionId = "crashed-session-abc"
        metadata.oldSessionTimeInterval = TimeInterval(1_600_000_000)
        metadata.oldSessionSampledIn = nil
        sessionManager.sessionMetadata = metadata

        let attrs = Dictionary(uniqueKeysWithValues: sessionManager.lastLaunchSessionSpanAttributes())
        XCTAssertEqual(attrs[Keys.spanSessionSampledIn.rawValue], "true",
                       "Unknown prior decision must default to sampled-in so the crash can't be dropped by a beforeSend filter.")
    }

    func testLoadPrevSession_recoversPersistedSamplingDecision() {
        // First "launch" leaves its identity + sampling decision in the keychain.
        let keychain = MockKeyschainManager()
        _ = SessionMetadata(sessionId: "crashed-session", sessionCreationDate: 1_600_000_000, using: keychain)
        keychain.writeStringToKeychain(service: Keys.service.rawValue,
                                       key: Keys.keySessionSampledIn.rawValue,
                                       value: "false")

        // Relaunch: the fresh session's metadata recovers the crashed launch's state.
        let relaunch = SessionMetadata(sessionId: "fresh-session", sessionCreationDate: 1_700_000_000, using: keychain)

        XCTAssertEqual(relaunch.oldSessionId, "crashed-session")
        XCTAssertEqual(relaunch.oldSessionSampledIn, false,
                       "The crashed launch's sampling decision must be recovered alongside its identity.")
    }

    func testLoadPrevSession_withoutPersistedDecision_leavesNil() {
        // Prior launch written by an SDK version that predates the persisted decision.
        let keychain = MockKeyschainManager()
        _ = SessionMetadata(sessionId: "legacy-session", sessionCreationDate: 1_600_000_000, using: keychain)

        let relaunch = SessionMetadata(sessionId: "fresh-session", sessionCreationDate: 1_700_000_000, using: keychain)

        XCTAssertEqual(relaunch.oldSessionId, "legacy-session")
        XCTAssertNil(relaunch.oldSessionSampledIn,
                     "Absent keychain entry must stay nil so lastLaunchSessionSpanAttributes applies the sampled-in default.")
    }

    // MARK: - SessionContext parses the stamp (wire payload)

    func testSessionContext_parsesSampledOutStamp() throws {
        let context = try XCTUnwrap(SessionContext(otel: makeSpan(sampledIn: "false"), userMetadata: nil))

        XCTAssertFalse(context.isSessionSampledIn)
        let dict = context.getDictionary()
        XCTAssertEqual(dict[Keys.isSessionSampledIn.rawValue] as? Bool, false)
    }

    func testSessionContext_parsesSampledInStamp() throws {
        let context = try XCTUnwrap(SessionContext(otel: makeSpan(sampledIn: "true"), userMetadata: nil))

        XCTAssertTrue(context.isSessionSampledIn)
        XCTAssertEqual(context.getDictionary()[Keys.isSessionSampledIn.rawValue] as? Bool, true)
    }

    func testSessionContext_missingStamp_defaultsToSampledIn() throws {
        // Spans persisted by older SDK versions carry no stamp; they can only have
        // reached export on a sampled-in session, so the payload must say true.
        let context = try XCTUnwrap(SessionContext(otel: makeSpan(sampledIn: nil), userMetadata: nil))

        XCTAssertTrue(context.isSessionSampledIn)
        XCTAssertEqual(context.getDictionary()[Keys.isSessionSampledIn.rawValue] as? Bool, true)
    }

    // MARK: - beforeSend sees the flag; tampering with it has no effect

    func testBeforeSend_subsetExposesSampledOutFlag() throws {
        var observed: Bool?
        _ = try runThroughBeforeSend(sampledIn: "false") { cxRum in
            let session = cxRum[Keys.sessionContext.rawValue] as? [String: Any]
            observed = session?[Keys.isSessionSampledIn.rawValue] as? Bool
            return cxRum
        }

        XCTAssertEqual(observed, false,
                       "beforeSend must see isSessionSampledIn — filtering on it is the feature.")
    }

    func testBeforeSend_tamperingWithFlag_isIgnored() throws {
        let result = try runThroughBeforeSend(sampledIn: "false") { cxRum in
            var edit = cxRum
            var session = (edit[Keys.sessionContext.rawValue] as? [String: Any]) ?? [:]
            session[Keys.isSessionSampledIn.rawValue] = true
            edit[Keys.sessionContext.rawValue] = session
            return edit
        }

        let session = try XCTUnwrap(result.text[Keys.sessionContext.rawValue] as? [String: Any])
        XCTAssertEqual(session[Keys.isSessionSampledIn.rawValue] as? Bool, false,
                       "The SDK's sampling decision must survive a callback that rewrites it.")
        XCTAssertEqual(result.otel["cx_rum.session_context.isSessionSampledIn"] as? Bool, false,
                       "The otelSpan attribute mirror must carry the SDK's value, not the tampered one.")
    }

    func testPayload_sampledOutFlag_reachesTextAndOtelMirror() throws {
        let result = try runThroughBeforeSend(sampledIn: "false") { $0 }

        let session = try XCTUnwrap(result.text[Keys.sessionContext.rawValue] as? [String: Any])
        XCTAssertEqual(session[Keys.isSessionSampledIn.rawValue] as? Bool, false)
        XCTAssertEqual(result.otel["cx_rum.session_context.isSessionSampledIn"] as? Bool, false)
    }

    func testPayload_withoutBeforeSend_carriesFlagInTextAndStructBuiltMirror() throws {
        // No beforeSend: text.cx_rum comes straight from CxRumPayloadBuilder and the
        // otelSpan attributes from the struct-based mirror (not the dict rebuild).
        let result = try runThroughBeforeSend(sampledIn: "false", beforeSend: nil)

        let session = try XCTUnwrap(result.text[Keys.sessionContext.rawValue] as? [String: Any])
        XCTAssertEqual(session[Keys.isSessionSampledIn.rawValue] as? Bool, false)
        XCTAssertEqual(result.otel["cx_rum.session_context.isSessionSampledIn"] as? Bool, false)
    }

    // MARK: - Helpers

    /// networkRequest event type so instrumentation_data (and its attribute mirror) is emitted.
    private func makeSpan(sampledIn: String?) -> MockSpanData {
        var attributes: [String: Any] = [
            Keys.severity.rawValue: AttributeValue("3"),
            Keys.eventType.rawValue: AttributeValue(CoralogixEventType.networkRequest.rawValue),
            Keys.source.rawValue: AttributeValue("fetch"),
            Keys.environment.rawValue: AttributeValue("test"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
            SemanticAttributes.httpUrl.rawValue: AttributeValue("https://example.com"),
            SemanticAttributes.httpMethod.rawValue: AttributeValue("GET"),
            SemanticAttributes.httpStatusCode.rawValue: AttributeValue("200")
        ]
        if let sampledIn {
            attributes[Keys.spanSessionSampledIn.rawValue] = AttributeValue(sampledIn)
        }
        return MockSpanData(attributes: attributes,
                            startTime: Date(),
                            endTime: Date(),
                            spanId: "20",
                            traceId: "30",
                            name: "testSpan",
                            kind: 2,
                            statusCode: ["status": "ok"],
                            resources: [:])
    }

    private func runThroughBeforeSend(
        sampledIn: String?,
        beforeSend: (([String: Any]) -> [String: Any]?)?
    ) throws -> (text: [String: Any], otel: [String: Any]) {
        let options = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "test",
            application: "TestApp",
            version: "1.0.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: nil,
            beforeSend: beforeSend,
            debug: false
        )
        let cxSpan = try XCTUnwrap(CxSpan(
            otel: makeSpan(sampledIn: sampledIn),
            versionMetadata: VersionMetadata(appName: "TestApp", appVersion: "1.0.0"),
            sessionManager: SessionManager(),
            networkManager: NetworkManager(),
            viewManager: ViewManager(keyChain: KeychainManager()),
            metricsManager: MetricsManager(),
            options: options
        ))
        let dict = try XCTUnwrap(cxSpan.getDictionary())
        let textWrapper = try XCTUnwrap(dict[Keys.text.rawValue] as? [String: Any])
        let textCxRum = try XCTUnwrap(textWrapper[Keys.cxRum.rawValue] as? [String: Any])
        let inst = try XCTUnwrap(dict[Keys.instrumentationData.rawValue] as? [String: Any])
        let otelSpan = try XCTUnwrap(inst[Keys.otelSpan.rawValue] as? [String: Any])
        let attrs = try XCTUnwrap(otelSpan[Keys.attributes.rawValue] as? [String: Any])
        return (textCxRum, attrs)
    }
}
