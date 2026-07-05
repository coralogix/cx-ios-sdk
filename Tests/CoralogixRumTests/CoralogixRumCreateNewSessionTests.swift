//
//  CoralogixRumCreateNewSessionTests.swift
//
//  Verifies the public `createNewSession()` API: on demand it rotates the
//  session (fresh session ID), drives the rotation callbacks, and is a safe
//  no-op when the SDK is not initialized.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class CoralogixRumCreateNewSessionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Static SDK state can leak between tests if a prior init was not torn down.
        CoralogixRum.isInitialized = false
    }

    func testCreateNewSession_rotatesSessionId() {
        let rum = CoralogixRum(options: makeOptions())
        defer { rum.shutdown() }

        let oldSessionId = rum.getSessionId
        XCTAssertNotNil(oldSessionId, "A session must exist after a successful init.")

        rum.createNewSession()

        let newSessionId = rum.getSessionId
        XCTAssertNotNil(newSessionId)
        XCTAssertNotEqual(oldSessionId, newSessionId,
                          "createNewSession() must issue a fresh session ID.")
    }

    func testCreateNewSession_firesSessionRotationCallbacks() {
        let rum = CoralogixRum(options: makeOptions())
        defer { rum.shutdown() }

        guard let sessionManager = rum.sessionManager else {
            return XCTFail("SessionManager must exist after a successful init.")
        }

        // Callbacks fire synchronously inside setupSessionMetadata, so plain
        // Bool flags are enough — no async wait needed.
        var sessionEndedFired = false
        var sessionChangedFired = false
        sessionManager.sessionEndedCallback = { sessionEndedFired = true }
        sessionManager.sessionChangedCallback = { _ in sessionChangedFired = true }

        rum.createNewSession()

        XCTAssertTrue(sessionEndedFired,
                      "Rotating an existing session must fire sessionEndedCallback.")
        XCTAssertTrue(sessionChangedFired,
                      "createNewSession() must fire sessionChangedCallback with the new session ID.")
    }

    func testCreateNewSession_whenNotInitialized_isNoOp() {
        let rum = CoralogixRum(options: makeOptions())
        defer { rum.shutdown() }

        let sessionIdBefore = rum.getSessionId
        XCTAssertNotNil(sessionIdBefore)

        // Simulate an uninitialized SDK (e.g. after shutdown or a sampled-out init).
        CoralogixRum.isInitialized = false
        rum.createNewSession()

        XCTAssertEqual(rum.getSessionId, sessionIdBefore,
                       "createNewSession() must be a no-op when the SDK is not initialized.")
    }

    // MARK: - Helpers

    private func makeOptions() -> CoralogixExporterOptions {
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
            sessionSampleRate: 100,
            excludeFromSampling: [],
            instrumentations: nil,
            debug: false
        )
    }
}
