//
//  HybridTraceparentFlagTests.swift
//
//  The contract a hybrid wrapper (Flutter, React Native) relies on when it builds `traceparent` itself:
//  `networkRequestSampling()` gives the flag for a request starting now and the session it is for, and
//  the same answer echoed back as `traceparentSampled` / `traceparentSessionId` in
//  `setNetworkRequestContext` puts the event in the session the request started in — so the event and
//  the flag on the wire agree even when the session rotates while the request is in flight.
//
//  Reports go through the real bridge entry point and are observed post-filter through
//  `beforeSendCallBack`, which receives the encoded payload a hybrid bridge would.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

/// One exported `network-request` event: its URL, the session it was exported under and its view.
private struct ReportedRequest: Equatable {
    let url: String
    let sessionId: String?
    let isSessionSampledIn: Bool?
    let viewName: String?
    let viewNumber: Int?
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
        let view = cxRum[Keys.viewContext.rawValue] as? [String: Any]
        return ReportedRequest(url: url,
                               sessionId: session?[Keys.sessionId.rawValue] as? String,
                               isSessionSampledIn: session?[Keys.isSessionSampledIn.rawValue] as? Bool,
                               viewName: view?[Keys.view.rawValue] as? String,
                               viewNumber: cxRum[Keys.viewNumber.rawValue] as? Int)
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

    private func liveSessionId(of rum: CoralogixRum) throws -> String {
        try XCTUnwrap(rum.sessionManager?.sessionMetadata?.sessionId)
    }

    /// Rotates to a new session whose roll is `sampledIn` — what `createNewSession`, the first touch
    /// after an idle period or the 1-hour limit does to a request already in flight.
    private func rotateSession(of rum: CoralogixRum, sampledIn: Bool) throws {
        let sessionManager = try XCTUnwrap(rum.sessionManager)
        sessionManager.samplingRoller = { sampledIn }
        sessionManager.setupSessionMetadata()
        XCTAssertEqual(sessionManager.isSessionSampledIn, sampledIn, "Sanity: the rotation must take the planned roll.")
    }

    /// Reports a request the way a wrapper does when it completes, echoing what it was given at start.
    private func report(_ rum: CoralogixRum, path: String, echo: NetworkRequestSampling? = nil, sampledOnly: Any? = nil) {
        var dictionary: [String: Any] = [
            Keys.url.rawValue: "https://api.example.com/\(path)",
            Keys.host.rawValue: "api.example.com",
            Keys.method.rawValue: "GET",
            Keys.statusCode.rawValue: 200,
            Keys.fragments.rawValue: "/\(path)",
            Keys.schema.rawValue: "https",
            Keys.httpResponseBodySize.rawValue: 0
        ]
        if let echo {
            dictionary[Keys.traceparentSampled.rawValue] = echo.isSampled
            dictionary[Keys.traceparentSessionId.rawValue] = echo.sessionId
        }
        if let sampledOnly {
            dictionary[Keys.traceparentSampled.rawValue] = sampledOnly
        }
        rum.setNetworkRequestContext(dictionary: dictionary)
    }

    private func flush() {
        Thread.sleep(forTimeInterval: 0.3)
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func reported(_ path: String) -> ReportedRequest? {
        capture.requests.first { $0.url == "https://api.example.com/\(path)" }
    }

    // MARK: - networkRequestSampling(): the flag for a request starting now, and its session

    func testSampling_sampledIn_isSampledForTheLiveSession() throws {
        let rum = try startRUM(sampleRate: 100)

        XCTAssertEqual(rum.networkRequestSampling(), NetworkRequestSampling(isSampled: true, sessionId: try liveSessionId(of: rum)))
    }

    func testSampling_sampledOut_nothingExcluded_isNotSampled() throws {
        let rum = try startRUM(sampleRate: 0)

        XCTAssertFalse(rum.networkRequestSampling().isSampled)
    }

    func testSampling_sampledOut_networkExcluded_isSampled() throws {
        let rum = try startRUM(sampleRate: 0, exclude: [.network])

        XCTAssertTrue(rum.networkRequestSampling().isSampled)
    }

    func testSampling_sampledOut_onlyOtherInstrumentationsExcluded_isNotSampled() throws {
        let rum = try startRUM(sampleRate: 0, exclude: Set(ExcludableInstrumentation.allCases).subtracting([.network]))

        XCTAssertFalse(rum.networkRequestSampling().isSampled, "The rule is excludes(network), not \"anything excluded\".")
    }

    /// A wrapper honouring the flag must not send `01` for a request whose event the exporter drops
    /// because network reporting is off.
    func testSampling_networkOff_isNotSampledEvenSampledIn() throws {
        let rum = try startRUM(sampleRate: 100, instrumentations: [.network: false])

        XCTAssertFalse(rum.networkRequestSampling().isSampled)
    }

    func testSampling_afterShutdown_hasNoDecisionAndNoSession() throws {
        let rum = try startRUM(sampleRate: 100)
        XCTAssertTrue(rum.networkRequestSampling().isSampled, "Sanity: the same SDK answers true while running.")

        rum.shutdown()
        self.rum = nil

        XCTAssertEqual(rum.networkRequestSampling(), NetworkRequestSampling(isSampled: false, sessionId: nil))
    }

    /// The answer must belong to the session the request starts in. A session past its 1-hour limit
    /// rotates on the next read, so the call itself has to do that read first, as a native span does —
    /// and the session it returns must be the new one, paired with the new one's decision.
    func testSampling_sessionPastItsHour_rotatesFirstAndAnswersForTheNewSession() throws {
        let rum = try startRUM(sampleRate: 100)
        let sessionManager = try XCTUnwrap(rum.sessionManager)
        var metadata = try XCTUnwrap(sessionManager.sessionMetadata)
        let staleSessionId = metadata.sessionId
        metadata.sessionCreationDate = Date().addingTimeInterval(-3601).timeIntervalSince1970
        sessionManager.sessionMetadata = metadata
        sessionManager.samplingRoller = { false }

        let sampling = rum.networkRequestSampling()

        XCTAssertFalse(sampling.isSampled,
                       "The expired session was sampled in; the session the request actually starts in is not.")
        XCTAssertNotEqual(sampling.sessionId, staleSessionId, "The call must have performed the due rotation.")
        XCTAssertEqual(sampling.sessionId, sessionManager.sessionMetadata?.sessionId)
    }

    // MARK: - The echo: the event belongs to the session the request started in

    /// Started in a sampled-in session (header `01`), completed after a rotation into a sampled-out one.
    /// The event is reported in the session it started in, under that session's decision — exactly where
    /// a native request's would be. Without the echo — an older wrapper — today's behaviour holds and the
    /// completion-time session drops it, which also proves the capture would have seen a drop. A `true`
    /// flag without its session must not force the event into the sampled-out live session either.
    func testRotatedOutMidRequest_echoReportsItInTheStartSession_withoutTheEchoItIsDropped() throws {
        let rum = try startRUM(sampleRate: 100)
        let atStart = rum.networkRequestSampling()
        XCTAssertTrue(atStart.isSampled)
        try rotateSession(of: rum, sampledIn: false)

        report(rum, path: "echoed", echo: atStart)
        report(rum, path: "no-echo")
        report(rum, path: "flag-without-session", sampledOnly: true)
        flush()

        let request = try XCTUnwrap(reported("echoed"), "A `01` request must report its event. Saw \(capture.urls).")
        XCTAssertEqual(request.sessionId, atStart.sessionId, "The event belongs to the session it started in.")
        XCTAssertEqual(request.isSessionSampledIn, true)
        XCTAssertNil(reported("no-echo"), "Without the echo the completion-time session decides. Saw \(capture.urls).")
        XCTAssertNil(reported("flag-without-session"),
                     "A flag alone must not surface a sampled-out session. Saw \(capture.urls).")
    }

    /// The new session navigated on; the request still reports the view its own session ended on, never
    /// the live session's view — whose number restarted with it.
    func testRotatedMidRequest_carriesTheViewItsStartSessionEndedOn() throws {
        let rum = try startRUM(sampleRate: 100)
        let viewManager = try XCTUnwrap(rum.coralogixExporter?.getViewManager())
        for name in ["first", "second", "third"] {
            viewManager.set(cxView: CXView(state: .notifyOnAppear, name: name))
        }
        XCTAssertEqual(viewManager.getViewNumber(), 2, "Precondition: the start session ends on its own view 2")
        let atStart = rum.networkRequestSampling()
        try rotateSession(of: rum, sampledIn: true)
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "fourth"))
        XCTAssertEqual(viewManager.getViewNumber(), 1, "Precondition: the live session is on its own view 1")

        report(rum, path: "echoed", echo: atStart)
        report(rum, path: "no-echo")
        flush()

        let request = try XCTUnwrap(reported("echoed"), "Saw \(capture.urls).")
        XCTAssertEqual(request.viewName, "third")
        XCTAssertEqual(request.viewNumber, 2)
        XCTAssertEqual(reported("no-echo")?.viewName, "fourth", "Control: a live-session event has the live view.")
    }

    /// Started in a sampled-out session (header `00`), completed after a rotation into a sampled-in one.
    /// The echoed `false` drops the event, Bool or stringified; the echo-less control is kept.
    func testRotatedInMidRequest_echoedFalseDropsTheEvent_withoutTheEchoItIsKept() throws {
        let rum = try startRUM(sampleRate: 0)
        let atStart = rum.networkRequestSampling()
        XCTAssertFalse(atStart.isSampled)
        try rotateSession(of: rum, sampledIn: true)

        report(rum, path: "echoed", echo: atStart)
        report(rum, path: "echoed-false-string", sampledOnly: "false")
        report(rum, path: "no-echo")
        flush()

        XCTAssertNotNil(reported("no-echo"), "Sanity: a sampled-in session reports. Saw \(capture.urls).")
        XCTAssertNil(reported("echoed"), "A `00` request must not report its event. Saw \(capture.urls).")
        XCTAssertNil(reported("echoed-false-string"), "Bridges that stringify must be honoured too. Saw \(capture.urls).")
    }

    /// No rotation: the start session is still the live one and the event carries its own stamp.
    func testNoRotation_echoKeepsTheLiveSession() throws {
        let rum = try startRUM(sampleRate: 100)
        let atStart = rum.networkRequestSampling()

        report(rum, path: "echoed", echo: atStart)
        flush()

        let request = try XCTUnwrap(reported("echoed"), "Saw \(capture.urls).")
        XCTAssertEqual(request.sessionId, atStart.sessionId)
        XCTAssertEqual(request.isSessionSampledIn, true)
    }

    /// With network excluded every running answer is `01` and says nothing about the session, so the start
    /// session's own decision is what the event reports: here sampled out, rotated into a sampled-in one.
    func testNetworkExcluded_rotatedMidRequest_reportsTheStartSessionsRealStamp() throws {
        let rum = try startRUM(sampleRate: 0, exclude: [.network])
        let atStart = rum.networkRequestSampling()
        XCTAssertTrue(atStart.isSampled)
        try rotateSession(of: rum, sampledIn: true)

        report(rum, path: "echoed", echo: atStart)
        flush()

        let request = try XCTUnwrap(reported("echoed"), "Excluding network exports the event. Saw \(capture.urls).")
        XCTAssertEqual(request.sessionId, atStart.sessionId)
        XCTAssertEqual(request.isSessionSampledIn, false, "The start session was sampled out; the payload must say so.")
    }

    /// A request that starts before initialization finishes gets `false` with no session, so `00` — and if
    /// it completes once the SDK is up, network being excluded must not let its event out against that
    /// header. The echo-less control is reported on the exclusion, so the capture would have seen it.
    func testNetworkExcluded_echoedFalseStillDropsTheEvent() throws {
        let rum = try startRUM(sampleRate: 0, exclude: [.network])

        report(rum, path: "echoed", echo: NetworkRequestSampling(isSampled: false, sessionId: nil))
        report(rum, path: "no-echo")
        flush()

        XCTAssertNotNil(reported("no-echo"), "Sanity: excluding network reports the event. Saw \(capture.urls).")
        XCTAssertNil(reported("echoed"), "A `00` request must not report its event. Saw \(capture.urls).")
    }

    /// Two rotations during one request: the start session is two back and is still where it is reported.
    func testStartSessionTwoRotationsBack_isStillWhereItIsReported() throws {
        let rum = try startRUM(sampleRate: 100)
        let atStart = rum.networkRequestSampling()
        try rotateSession(of: rum, sampledIn: false)
        try rotateSession(of: rum, sampledIn: false)

        report(rum, path: "echoed", echo: atStart)
        flush()

        let request = try XCTUnwrap(reported("echoed"), "A `01` request must report its event. Saw \(capture.urls).")
        XCTAssertEqual(request.sessionId, atStart.sessionId)
        XCTAssertEqual(request.isSessionSampledIn, true)
    }

    /// A session no longer known — older than the kept history, or one this process never had — must not
    /// have its request reported in another session. The echo-less control in the same sampled-in session
    /// is reported, so the capture would have seen it.
    func testUnknownStartSession_dropsTheEvent() throws {
        let rum = try startRUM(sampleRate: 100)

        report(rum, path: "unknown-session", echo: NetworkRequestSampling(isSampled: true, sessionId: "not-a-session"))
        report(rum, path: "no-echo")
        flush()

        XCTAssertNotNil(reported("no-echo"), "Sanity: a sampled-in session reports. Saw \(capture.urls).")
        XCTAssertNil(reported("unknown-session"), "Saw \(capture.urls).")
    }

    /// The history is bounded: a session more than eight rotations back is no longer known.
    func testStartSessionBeyondTheKeptHistory_dropsTheEvent() throws {
        let rum = try startRUM(sampleRate: 100)
        let atStart = rum.networkRequestSampling()
        for _ in 0..<8 { try rotateSession(of: rum, sampledIn: true) }
        let stillKept = rum.networkRequestSampling()
        try rotateSession(of: rum, sampledIn: true)

        report(rum, path: "beyond-history", echo: atStart)
        report(rum, path: "eighth-back", echo: stillKept)
        flush()

        XCTAssertEqual(reported("eighth-back")?.sessionId, stillKept.sessionId,
                       "Control: a session within the kept history is reported in. Saw \(capture.urls).")
        XCTAssertNil(reported("beyond-history"), "Saw \(capture.urls).")
    }
}
