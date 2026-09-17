//
//  CrashBootstrapTests.swift
//
//  PLCrashReporter is enabled from `CRXCrashBootstrap.load`, before `main()`, so that a crash
//  reporter the host app configures first (Firebase Crashlytics) reinstates our signal handlers
//  at crash time instead of replacing them. These tests pin the two things that ordering depends
//  on: that the load-time install happened, and that `initializeCrashInstrumentation` adopts that
//  instance rather than enabling one of its own — which would put our handler back behind
//  whatever the host configured and reintroduce the loss.
//

import XCTest
import CrashReporter
import CoralogixCrashBootstrap

@testable import Coralogix

final class CrashBootstrapTests: XCTestCase {

    /// `+load` ran in this process and enabled a reporter. Fails if the bootstrap is dropped from
    /// the target, if `+load` is removed, or if enabling starts failing.
    func testBootstrapEnabledAReporterAtLoad() {
        XCTAssertNotNil(CRXCrashBootstrap.reporter,
                        "+load did not enable PLCrashReporter: \(String(describing: CRXCrashBootstrap.enableError))")
        XCTAssertNil(CRXCrashBootstrap.enableError)
    }

    /// The test host sets no opt-out key, so the load-time install is the path taken.
    func testBootstrapIsNotDisabledWithoutTheInfoPlistKey() {
        XCTAssertFalse(CRXCrashBootstrap.disabledByHostApp)
    }

    /// The reporter crash recovery uses is the one enabled at load, not a new one. This is the
    /// whole point of the change: creating a second reporter here would register our handlers
    /// after the host's crash reporter and lose the ordering the bootstrap exists to win.
    func testInstalledCrashReporterAdoptsTheBootstrappedInstance() throws {
        let bootstrapped = try XCTUnwrap(CRXCrashBootstrap.reporter)
        let resolved = try XCTUnwrap(CoralogixRum.installedCrashReporter())
        XCTAssertTrue(resolved === bootstrapped)
    }

    /// A supplied candidate is returned as-is, so the adoption path never reaches the fallback.
    func testInstalledCrashReporterReturnsTheSuppliedCandidate() throws {
        let candidate = try XCTUnwrap(
            PLCrashReporter(configuration: PLCrashReporterConfig(signalHandlerType: .BSD,
                                                                symbolicationStrategy: []))
        )
        let resolved = try XCTUnwrap(CoralogixRum.installedCrashReporter(candidate: candidate))
        XCTAssertTrue(resolved === candidate)
    }

    // The `candidate: nil` fallback is deliberately not exercised: it calls `enable()`, which
    // installs signal handlers process-wide and cannot be undone in `tearDown`. Its behaviour —
    // enabling a reporter at init — is what the SDK did before this target existed and is covered
    // by the rest of the crash suite.
}
