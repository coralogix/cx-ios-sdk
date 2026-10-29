//
//  HybridTraceparentFlagTests.swift
//
//  The contract a hybrid wrapper (Flutter, React Native) relies on when it builds `traceparent` itself:
//  `isNetworkRequestSampled()` gives the flag for a request starting now, and the same answer echoed
//  back as `traceparentSampled` in `setNetworkRequestContext` decides the reported event — so the
//  event and the flag on the wire agree even when the session rotates while the request is in flight.
//
//  Reports go through the real bridge entry point and are observed post-filter through
//  `beforeSendCallBack`, which receives the encoded payload a hybrid bridge would.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

/// One exported `network-request` event: its URL and the session sampling stamp it was exported under.
private struct ReportedRequest: Equatable {
    let url: String
    let isSessionSampledIn: Bool?
}

private final class NetworkEventCapture {
    private let lock = NSLock()
    private var values: [ReportedRequest] = []

    var requests: [ReportedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    var urls: [String] { requests.map(\.url) }

    func beforeSendCallback() -> ([[String: Any]]) -> Void {
        return { batch in
            let reported = batch.compactMap(Self.networkRequest(in:))
            self.lock.lock()
            self.values.append(contentsOf: reported)
            self.lock.unlock()
        }
    }

    private static func networkRequest(in dict: [String: Any]) -> ReportedRequest? {
        guard let text = dict[Keys.text.rawValue] as? [String: Any],
              let cxRum = text[Keys.cxRum.rawValue] as? [String: Any],
              let network = cxRum[Keys.networkRequestContext.rawValue] as? [String: Any],
              let url = network[Keys.url.rawValue] as? String else {
            return nil
        }
        let session = cxRum[Keys.sessionContext.rawValue] as? [String: Any]
        return ReportedRequest(url: url, isSessionSampledIn: session?[Keys.isSessionSampledIn.rawValue] as? Bool)
    }
}

final class HybridTraceparentFlagTests: XCTestCase {

    private var rum: CoralogixRum?
    private var capture: NetworkEventCapture!

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
        capture = NetworkEventCapture()
    }

    override func tearDown() {
        rum?.shutdown()
        rum = nil
        CoralogixRum.isInitialized = false
        super.tearDown()
    }

    @discardableResult
    private func startRUM(sampleRate: Int,
                          exclude: Set<ExcludableInstrumentation> = [],
                          instrumentations: [CoralogixExporterOptions.InstrumentationType: Bool]? = nil) throws -> CoralogixRum {
        var options = makeSamplingOptions(sampleRate: sampleRate,
                                          exclude: exclude,
                                          instrumentations: instrumentations,
                                          traceParentInHeader: traceParentEnabled)
        options.beforeSendCallBack = capture.beforeSendCallback()
        let rum = CoralogixRum(options: options, sdkFramework: .flutter(version: "1.0.0"))
        self.rum = rum
        try XCTUnwrap(rum.coralogixExporter).spanUploader = SamplingMockSpanUploader()
        return rum
    }

    /// Rotates to a new session whose roll is `sampledIn` — what `createNewSession`, the first touch
    /// after an idle period or the 1-hour limit does to a request already in flight.
    private func rotateSession(of rum: CoralogixRum, sampledIn: Bool) throws {
        let sessionManager = try XCTUnwrap(rum.sessionManager)
        sessionManager.samplingRoller = { sampledIn }
        sessionManager.setupSessionMetadata()
        XCTAssertEqual(sessionManager.isSessionSampledIn, sampledIn, "Sanity: the rotation must take the planned roll.")
    }

    private func report(_ rum: CoralogixRum, path: String, traceparentSampled: Any? = nil) {
        var dictionary: [String: Any] = [
            Keys.url.rawValue: "https://api.example.com/\(path)",
            Keys.host.rawValue: "api.example.com",
            Keys.method.rawValue: "GET",
            Keys.statusCode.rawValue: 200,
            Keys.fragments.rawValue: "/\(path)",
            Keys.schema.rawValue: "https",
            Keys.httpResponseBodySize.rawValue: 0
        ]
        if let traceparentSampled {
            dictionary[Keys.traceparentSampled.rawValue] = traceparentSampled
        }
        rum.setNetworkRequestContext(dictionary: dictionary)
    }

    private func flush() {
        Thread.sleep(forTimeInterval: 0.3)
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func reported(_ path: String) -> Bool {
        capture.urls.contains("https://api.example.com/\(path)")
    }

    // MARK: - isNetworkRequestSampled(): the flag for a request starting now

    func testIsNetworkRequestSampled_sampledIn_isTrue() throws {
        let rum = try startRUM(sampleRate: 100)

        XCTAssertTrue(rum.isNetworkRequestSampled())
    }

    func testIsNetworkRequestSampled_sampledOut_nothingExcluded_isFalse() throws {
        let rum = try startRUM(sampleRate: 0)

        XCTAssertFalse(rum.isNetworkRequestSampled())
    }

    func testIsNetworkRequestSampled_sampledOut_networkExcluded_isTrue() throws {
        let rum = try startRUM(sampleRate: 0, exclude: [.network])

        XCTAssertTrue(rum.isNetworkRequestSampled())
    }

    func testIsNetworkRequestSampled_sampledOut_onlyOtherInstrumentationsExcluded_isFalse() throws {
        let rum = try startRUM(sampleRate: 0, exclude: Set(ExcludableInstrumentation.allCases).subtracting([.network]))

        XCTAssertFalse(rum.isNetworkRequestSampled(), "The rule is excludes(network), not \"anything excluded\".")
    }

    /// A wrapper honouring the flag must not send `01` for a request whose event the exporter drops
    /// because network reporting is off.
    func testIsNetworkRequestSampled_networkOff_isFalseEvenSampledIn() throws {
        let rum = try startRUM(sampleRate: 100, instrumentations: [.network: false])

        XCTAssertFalse(rum.isNetworkRequestSampled())
    }

    func testIsNetworkRequestSampled_afterShutdown_isFalse() throws {
        let rum = try startRUM(sampleRate: 100)
        XCTAssertTrue(rum.isNetworkRequestSampled(), "Sanity: the same SDK answers true while running.")

        rum.shutdown()
        self.rum = nil

        XCTAssertFalse(rum.isNetworkRequestSampled())
    }

    /// The answer must belong to the session the request starts in. A session past its 1-hour limit
    /// rotates on the next read, so the call itself has to do that read first, as a native span does.
    func testIsNetworkRequestSampled_sessionPastItsHour_rotatesFirstAndAnswersForTheNewSession() throws {
        let rum = try startRUM(sampleRate: 100)
        let sessionManager = try XCTUnwrap(rum.sessionManager)
        var metadata = try XCTUnwrap(sessionManager.sessionMetadata)
        let staleSessionId = metadata.sessionId
        metadata.sessionCreationDate = Date().addingTimeInterval(-3601).timeIntervalSince1970
        sessionManager.sessionMetadata = metadata
        sessionManager.samplingRoller = { false }

        XCTAssertFalse(rum.isNetworkRequestSampled(),
                       "The expired session was sampled in; the session the request actually starts in is not.")
        XCTAssertNotEqual(sessionManager.sessionMetadata?.sessionId, staleSessionId,
                          "The call must have performed the due rotation.")
    }

    // MARK: - traceparentSampled: the start-time decision decides the event

    /// Started in a sampled-in session (header `01`), completed after a rotation into a sampled-out
    /// one. The echoed decision keeps the event the flag promised; the request reported without the
    /// key — an older wrapper — keeps today's behaviour and is dropped, which also proves the capture
    /// would have seen a drop.
    func testRotatedOutMidRequest_echoedTrueKeepsTheEvent_withoutTheKeyItIsDropped() throws {
        let rum = try startRUM(sampleRate: 100)
        XCTAssertTrue(rum.isNetworkRequestSampled())
        try rotateSession(of: rum, sampledIn: false)

        report(rum, path: "echoed-true", traceparentSampled: true)
        report(rum, path: "no-key")
        flush()

        XCTAssertTrue(reported("echoed-true"), "A `01` request must report its event. Saw \(capture.urls).")
        XCTAssertFalse(reported("no-key"), "Without the key the completion-time session decides. Saw \(capture.urls).")
        XCTAssertEqual(capture.requests.first { $0.url.hasSuffix("echoed-true") }?.isSessionSampledIn, true,
                       "The event is stamped with the decision of the session it started in.")
    }

    /// Started in a sampled-out session (header `00`), completed after a rotation into a sampled-in
    /// one. The echoed decision drops the event, Bool or stringified; the key-less control is kept.
    func testRotatedInMidRequest_echoedFalseDropsTheEvent_withoutTheKeyItIsKept() throws {
        let rum = try startRUM(sampleRate: 0)
        XCTAssertFalse(rum.isNetworkRequestSampled())
        try rotateSession(of: rum, sampledIn: true)

        report(rum, path: "echoed-false", traceparentSampled: false)
        report(rum, path: "echoed-false-string", traceparentSampled: "false")
        report(rum, path: "no-key")
        flush()

        XCTAssertTrue(reported("no-key"), "Sanity: a sampled-in session reports. Saw \(capture.urls).")
        XCTAssertFalse(reported("echoed-false"), "A `00` request must not report its event. Saw \(capture.urls).")
        XCTAssertFalse(reported("echoed-false-string"), "Bridges that stringify must be honoured too. Saw \(capture.urls).")
    }

    /// A request that starts before initialization finishes gets `false`, so `00` — and if it completes
    /// once the SDK is up, network being excluded must not let its event out against that header. The
    /// key-less control is reported on the exclusion, so the capture would have seen it.
    func testNetworkExcluded_echoedFalseStillDropsTheEvent() throws {
        let rum = try startRUM(sampleRate: 0, exclude: [.network])

        report(rum, path: "echoed-false", traceparentSampled: false)
        report(rum, path: "no-key")
        flush()

        XCTAssertTrue(reported("no-key"), "Sanity: excluding network reports the event. Saw \(capture.urls).")
        XCTAssertFalse(reported("echoed-false"), "A `00` request must not report its event. Saw \(capture.urls).")
    }

    /// With network excluded a running SDK always answers `01`, which says nothing about the session, so
    /// it must not overwrite the stamp: the event is exported on the exclusion and keeps reporting the
    /// session as sampled out.
    func testNetworkExcluded_echoedTrue_leavesTheSessionStampAlone() throws {
        let rum = try startRUM(sampleRate: 0, exclude: [.network])
        XCTAssertTrue(rum.isNetworkRequestSampled())

        report(rum, path: "excluded", traceparentSampled: true)
        flush()

        let request = try XCTUnwrap(capture.requests.first { $0.url.hasSuffix("excluded") },
                                    "Excluding network exports the event. Saw \(capture.urls).")
        XCTAssertEqual(request.isSessionSampledIn, false,
                       "The session is sampled out; the payload must keep saying so.")
    }
}
