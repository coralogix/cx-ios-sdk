//
//  SessionReplaySamplingGateTests.swift
//
//  Session replay asks the Coralogix module whether the current session is sampled in before
//  every capture (`CoralogixInterface.isSessionSampledIn`). This pins the answer that module
//  gives: it is the session's own roll, and it follows the roll across rotation in both
//  directions rather than being latched at init.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class SessionReplaySamplingGateTests: XCTestCase {

    private var rum: CoralogixRum?

    override func setUpWithError() throws {
        try super.setUpWithError()
        CoralogixRum.isInitialized = false
    }

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        CoralogixRum.isInitialized = false
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        try super.tearDownWithError()
    }

    private func makeRum(sampleRate: Int) throws -> CoralogixRum {
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: sampleRate, exclude: []))
        self.rum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter, "A sampled-out session still initializes.")
        exporter.spanUploader = SamplingMockSpanUploader()
        return rum
    }

    func testSampledOutSession_answersSampledOut() throws {
        let rum = try makeRum(sampleRate: 0)
        XCTAssertFalse(rum.isSessionSampledIn())
    }

    func testSampledInSession_answersSampledIn() throws {
        let rum = try makeRum(sampleRate: 100)
        XCTAssertTrue(rum.isSessionSampledIn())
    }

    /// The instance session replay actually talks to is the one registered on `SdkManager`, so
    /// the answer has to come through that indirection, not only from the instance directly.
    func testAnswerIsReachableThroughTheRegisteredInterface() throws {
        _ = try makeRum(sampleRate: 0)
        let registered = try XCTUnwrap(SdkManager.shared.getCoralogixSdk(),
                                       "init registers the Coralogix module with SdkManager")
        XCTAssertFalse(registered.isSessionSampledIn())
    }

    func testRotationIntoSampledIn_flipsTheAnswer() throws {
        let rum = try makeRum(sampleRate: 0)
        let sessionManager = try XCTUnwrap(rum.sessionManager)
        XCTAssertFalse(rum.isSessionSampledIn(), "Precondition: the first roll was sampled out.")

        sessionManager.samplingRoller = { true }
        rum.createNewSession()

        XCTAssertTrue(rum.isSessionSampledIn(),
                      "a rotation that rolls sampled in must let session replay capture again")
    }

    func testRotationIntoSampledOut_flipsTheAnswer() throws {
        let rum = try makeRum(sampleRate: 100)
        let sessionManager = try XCTUnwrap(rum.sessionManager)
        XCTAssertTrue(rum.isSessionSampledIn(), "Precondition: the first roll was sampled in.")

        sessionManager.samplingRoller = { false }
        rum.createNewSession()

        XCTAssertFalse(rum.isSessionSampledIn(),
                       "a rotation that rolls sampled out must stop session replay capturing")
    }
}
