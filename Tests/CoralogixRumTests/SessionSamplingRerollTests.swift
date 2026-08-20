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

    // MARK: - The callback carries its own rotation's decision

    func testSamplingCallback_receivesTheDecisionRolledForThatRotation() throws {
        // Guards against resolving the decision by re-reading `isSessionSampledIn` when the callback
        // runs: that reads whatever the newest rotation left, so a concurrent rotation could hide a
        // sampled-in transition from the callback meant to act on it. Passing it as an argument keeps
        // the decision paired with the rotation that produced it.
        let rum = CoralogixRum(options: makeOptions(sampleRate: 100, exclude: []))
        defer { rum.shutdown() }
        let sessionManager = try XCTUnwrap(rum.sessionManager)

        var rolled: [Bool] = []
        var observed: [Bool] = []
        let plan = [true, false, true, true, false]
        var next = 0

        sessionManager.samplingRoller = {
            let decision = plan[min(next, plan.count - 1)]
            next += 1
            rolled.append(decision)
            return decision
        }
        sessionManager.samplingReevaluationCallback = { _, sampledIn in observed.append(sampledIn) }

        for _ in plan { sessionManager.setupSessionMetadata() }

        XCTAssertEqual(observed, rolled,
                       "Each callback must report the decision rolled for its own rotation, in order.")
    }

    func testSamplingCallback_underConcurrentRotations_reportsEveryDecisionExactlyOnce() throws {
        // The invariant that a re-read cannot hold: however the rotations interleave, the decisions
        // the callbacks report must be exactly the decisions that were rolled — same count of each.
        let rum = CoralogixRum(options: makeOptions(sampleRate: 100, exclude: []))
        defer { rum.shutdown() }
        let sessionManager = try XCTUnwrap(rum.sessionManager)

        let stateLock = NSLock()
        var rolledTrue = 0
        var observedTrue = 0
        var observedTotal = 0
        var counter = 0

        sessionManager.samplingRoller = {
            stateLock.lock()
            defer { stateLock.unlock() }
            counter += 1
            let decision = counter % 2 == 0
            if decision { rolledTrue += 1 }
            return decision
        }
        sessionManager.samplingReevaluationCallback = { _, sampledIn in
            stateLock.lock()
            defer { stateLock.unlock() }
            observedTotal += 1
            if sampledIn { observedTrue += 1 }
        }

        let rotations = 40
        let queue = DispatchQueue(label: "rotations", attributes: .concurrent)
        let group = DispatchGroup()
        for _ in 0..<rotations {
            queue.async(group: group) { sessionManager.setupSessionMetadata() }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success, "Rotations must finish.")

        stateLock.lock()
        let (total, seenTrue, expectedTrue) = (observedTotal, observedTrue, rolledTrue)
        stateLock.unlock()

        XCTAssertEqual(total, rotations, "Every rotation must fire the callback exactly once.")
        XCTAssertEqual(seenTrue, expectedTrue,
                       "The sampled-in decisions reported must match the sampled-in decisions rolled.")
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
