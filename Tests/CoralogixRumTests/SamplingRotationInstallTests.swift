//
//  SamplingRotationInstallTests.swift
//
//  Instrumentation eligibility is resolved at init from the session's first sampling roll, but the
//  roll is repeated on every session rotation. A session that starts sampled out installs almost
//  nothing, so when a rotation rolls it sampled IN those instrumentations have to be installed then
//  — otherwise the session reports only what survives without them for the rest of the process.
//
//  The top-up must also be idempotent. None of the `initialize*Instrumentation()` functions are:
//  they register NotificationCenter observers, start monitors and install swizzles. Installing one
//  twice would double every event it produces, which is worse than the gap it closes.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class SamplingRotationInstallTests: XCTestCase {

    private var rum: CoralogixRum?
    private var capture: EventTypeCapture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        CoralogixRum.isInitialized = false
        capture = EventTypeCapture()
    }

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        CoralogixRum.isInitialized = false
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        try super.tearDownWithError()
    }

    /// Starts a session that rolls sampled OUT, then hands back a manager whose next roll lands IN.
    private func startSampledOutSession() throws -> SessionManager {
        let options = makeSamplingOptions(sampleRate: 0,
                                         exclude: [],
                                         tracesExporter: capture.tracesExporterCallback())
        let rum = CoralogixRum(options: options)
        self.rum = rum

        let exporter = try XCTUnwrap(rum.coralogixExporter, "A sampled-out session still initializes.")
        exporter.spanUploader = SamplingMockSpanUploader()
        XCTAssertEqual(exporter.isCurrentSessionSampledIn(), false, "Precondition: this session is sampled out.")

        let sessionManager = try XCTUnwrap(rum.sessionManager)
        sessionManager.samplingRoller = { true }
        return sessionManager
    }

    private func flush() {
        Thread.sleep(forTimeInterval: 0.3)
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private var lifeCycleEventCount: Int {
        capture.eventTypes.filter { $0 == CoralogixEventType.lifeCycle.rawValue }.count
    }

    func testRotationIntoSampledIn_installsInstrumentationSkippedAtInit() throws {
        let sessionManager = try startSampledOutSession()

        // Nothing lifecycle-shaped can be produced yet: the observers were never registered.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        flush()
        XCTAssertEqual(lifeCycleEventCount, 0,
                       "Sampled out with an empty exclude list: lifecycle instrumentation must not be installed.")

        rum?.createNewSession()
        XCTAssertTrue(sessionManager.isSessionSampledIn, "Precondition: the rotation rolled sampled in.")

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        flush()
        XCTAssertEqual(lifeCycleEventCount, 1,
                       "After rotating into a sampled-in session lifecycle events must resume. Saw \(capture.eventTypes).")
    }

    func testRepeatedRotations_doNotDuplicateInstrumentation() throws {
        let sessionManager = try startSampledOutSession()

        rum?.createNewSession()
        rum?.createNewSession()
        rum?.createNewSession()
        XCTAssertTrue(sessionManager.isSessionSampledIn)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        flush()

        XCTAssertEqual(lifeCycleEventCount, 1,
                       "One notification must yield one event however many rotations occurred — duplicated observers would multiply it. Saw \(capture.eventTypes).")
    }

    func testRotationStayingSampledOut_installsNothingExtra() throws {
        let options = makeSamplingOptions(sampleRate: 0,
                                         exclude: [],
                                         tracesExporter: capture.tracesExporterCallback())
        let rum = CoralogixRum(options: options)
        self.rum = rum
        try XCTUnwrap(rum.coralogixExporter).spanUploader = SamplingMockSpanUploader()

        // Roller keeps returning false, so the rotation re-rolls sampled out.
        rum.createNewSession()
        XCTAssertEqual(try XCTUnwrap(rum.sessionManager).isSessionSampledIn, false)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        flush()

        XCTAssertEqual(lifeCycleEventCount, 0,
                       "Still sampled out: nothing new becomes eligible. Saw \(capture.eventTypes).")
    }
}
