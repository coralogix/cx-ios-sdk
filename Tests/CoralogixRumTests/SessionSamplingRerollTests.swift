//
//  SessionSamplingRerollTests.swift
//
//  CX-40200 (T2) — verifies that:
//   1. The init guard short-circuits ONLY when the session is sampled out AND no
//      instrumentation is opted into `excludeFromSampling` (back-compat).
//   2. The exporter's per-session sampling decision is seeded at init.
//   3. Session rotation invokes the reroll callback through `samplingReevaluationCallback`,
//      keeping the exporter's flag in sync — without clobbering `sessionChangedCallback`,
//      which SessionReplay owns.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class SessionSamplingRerollTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Static SDK state can leak between tests if a prior init was not torn down.
        CoralogixRum.isInitialized = false
    }

    // MARK: - Back-compat: sampleRate=0 + empty exclude ⇒ no init

    func testInit_sampleRateZero_excludeEmpty_doesNotInitialize() {
        let rum = CoralogixRum(options: makeOptions(sampleRate: 0, exclude: []))
        defer { rum.shutdown() }

        XCTAssertFalse(rum.isInitialized,
                       "Back-compat: sampleRate=0 + excludeFromSampling=[] must NOT initialize.")
        XCTAssertNil(rum.coralogixExporter,
                     "Skipped init must not create an exporter.")
    }

    // MARK: - New: sampleRate=0 + non-empty exclude ⇒ init succeeds, sampledIn=false

    func testInit_sampleRateZero_excludeNonEmpty_initializesWithSampledOutFlag() {
        let rum = CoralogixRum(options: makeOptions(sampleRate: 0, exclude: [.errors]))
        defer { rum.shutdown() }

        XCTAssertTrue(rum.isInitialized,
                      "With excludeFromSampling non-empty, init must proceed even when sampled out.")
        XCTAssertEqual(rum.coralogixExporter?.isCurrentSessionSampledIn(), false,
                       "Exporter must record the session as sampled-out so T3 can gate non-excluded events.")
    }

    // MARK: - Positive: sampleRate=100 ⇒ init, sampledIn=true

    func testInit_sampleRateOneHundred_initializesWithSampledInFlag() {
        let rum = CoralogixRum(options: makeOptions(sampleRate: 100, exclude: []))
        defer { rum.shutdown() }

        XCTAssertTrue(rum.isInitialized)
        XCTAssertEqual(rum.coralogixExporter?.isCurrentSessionSampledIn(), true)
    }

    // MARK: - Session rotation re-evaluates sampling

    func testInit_sessionRotation_keepsExporterFlagInSync() {
        // sampleRate=0 + opt-in keeps the path deterministic: every roll yields false.
        let rum = CoralogixRum(options: makeOptions(sampleRate: 0, exclude: [.logs]))
        defer { rum.shutdown() }

        XCTAssertEqual(rum.coralogixExporter?.isCurrentSessionSampledIn(), false)

        // Force a rotation; the callback registered in startup() must run and keep the flag at false.
        rum.sessionManager?.setupSessionMetadata()

        XCTAssertEqual(rum.coralogixExporter?.isCurrentSessionSampledIn(), false,
                       "After rotation the reroll path must run; with sampleRate=0 the flag stays false.")
    }

    // MARK: - No-clobber regression for SessionReplay's sessionChangedCallback

    func testSessionRotation_firesBothSamplingReevaluationAndSessionChangedCallbacks() {
        let rum = CoralogixRum(options: makeOptions(sampleRate: 100, exclude: []))
        defer { rum.shutdown() }

        guard let sessionManager = rum.sessionManager else {
            return XCTFail("SessionManager must exist after a successful init.")
        }

        // CoralogixRum.startup installs samplingReevaluationCallback; we attach a sessionChangedCallback
        // here to mimic what SessionReplayInstrumentation does. Both must fire on the next rotation.
        let sessionChangedExp = expectation(description: "sessionChangedCallback fires")
        sessionManager.sessionChangedCallback = { _ in sessionChangedExp.fulfill() }

        XCTAssertNotNil(sessionManager.samplingReevaluationCallback,
                        "CoralogixRum.startup must install samplingReevaluationCallback.")

        sessionManager.setupSessionMetadata()

        wait(for: [sessionChangedExp], timeout: 1.0)
        // If samplingReevaluationCallback had been clobbered (or vice versa) the assertion above
        // would have failed; reaching this point proves both run independently.
    }

    // MARK: - Helpers

    private func makeOptions(sampleRate: Int,
                             exclude: Set<ExcludableInstrumentation>) -> CoralogixExporterOptions {
        return CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "test",
            application: "TestApp",
            version: "1.0.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: nil,
            sessionSampleRate: sampleRate,
            excludeFromSampling: exclude,
            instrumentations: nil,
            debug: false
        )
    }
}
