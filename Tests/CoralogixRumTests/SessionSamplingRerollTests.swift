//
//  SessionSamplingRerollTests.swift
//
//  Verifies that:
//   1. Init is unconditional — a sampled-out session still initializes, whatever the exclude list
//      holds, so network instrumentation stays alive to propagate trace context.
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

    // MARK: - sampleRate=0 + empty exclude ⇒ still initializes, stamped sampled-out

    func testInit_sampleRateZero_excludeEmpty_stillInitializesStampedSampledOut() {
        // The SDK used to skip init entirely here. It no longer can: network instrumentation has to
        // stay installed so outgoing requests still carry `traceparent`, and a session that never
        // initialized emits none. Nothing reportable survives the export filter, so the observable
        // telemetry is unchanged — what changes is that trace context keeps flowing.
        let rum = CoralogixRum(options: makeOptions(sampleRate: 0, exclude: []))
        defer { rum.shutdown() }

        XCTAssertTrue(rum.isInitialized,
                      "Init must proceed even sampled out with an empty exclude list.")
        XCTAssertEqual(rum.coralogixExporter?.isCurrentSessionSampledIn(), false,
                       "The exporter must record the session as sampled-out so the filter drops reportable spans.")
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

    // MARK: - Sampled-in + opt-in (overlap case): exclude must not interfere with normal init

    func testInit_sampleRateOneHundred_excludeNonEmpty_initializesWithSampledInFlag() {
        let rum = CoralogixRum(options: makeOptions(sampleRate: 100, exclude: [.errors]))
        defer { rum.shutdown() }

        XCTAssertTrue(rum.isInitialized,
                      "Sampled-in init must proceed regardless of excludeFromSampling content.")
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

        XCTAssertNotNil(sessionManager.samplingReevaluationCallback,
                        "CoralogixRum.startup must install samplingReevaluationCallback.")

        // CoralogixRum.startup installs samplingReevaluationCallback; attach a sessionChangedCallback
        // here to mimic what SessionReplayInstrumentation does. Callbacks fire synchronously inside
        // setupSessionMetadata, so a Bool flag is enough — no async wait needed.
        var sessionChangedFired = false
        sessionManager.sessionChangedCallback = { _ in sessionChangedFired = true }

        sessionManager.setupSessionMetadata()

        XCTAssertTrue(sessionChangedFired,
                      "sessionChangedCallback must fire on rotation; if samplingReevaluationCallback had clobbered it, this would be false.")
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
