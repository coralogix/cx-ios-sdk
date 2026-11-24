//
//  UserActionsDecouplingTests.swift
//
//  Unit tests for the user actions instrumentation gate:
//  - Native touch swizzles are installed in hybrid mode.
//  - RUM user_interaction spans are only emitted when userActions is enabled AND SDK is native.
//

import XCTest
@testable import Coralogix

final class UserActionsDecouplingTests: XCTestCase {

    // MARK: - shouldEmitUserActionSpan: native + userActions on/off

    func testShouldEmitUserActionSpan_native_userActionsEnabled_returnsTrue() {
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
            sessionSampleRate: 100,
            instrumentations: [.userActions: true],
            debug: false
        )
        let rum = CoralogixRum(options: options, sdkFramework: .swift)
        defer { rum.shutdown() }

        XCTAssertTrue(rum.shouldEmitUserActionSpan,
                      "Native SDK with userActions enabled must emit user action spans")
    }

    func testShouldEmitUserActionSpan_native_userActionsDisabled_returnsFalse() {
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
            sessionSampleRate: 100,
            instrumentations: [.userActions: false],
            debug: false
        )
        let rum = CoralogixRum(options: options, sdkFramework: .swift)
        defer { rum.shutdown() }

        XCTAssertFalse(rum.shouldEmitUserActionSpan,
                       "Native SDK with userActions disabled must not emit user action spans")
    }

    func testShouldEmitUserActionSpan_native_instrumentationsNil_returnsTrue() {
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
            sessionSampleRate: 100,
            instrumentations: nil,
            debug: false
        )
        let rum = CoralogixRum(options: options, sdkFramework: .swift)
        defer { rum.shutdown() }

        XCTAssertTrue(rum.shouldEmitUserActionSpan,
                      "Native SDK with instrumentations nil (default) must emit user action spans")
    }

    // MARK: - shouldEmitUserActionSpan: hybrid

    func testShouldEmitUserActionSpan_hybridFlutter_userActionsEnabled_returnsFalse() {
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
            sessionSampleRate: 100,
            instrumentations: [.userActions: true],
            debug: false
        )
        let rum = CoralogixRum(options: options, sdkFramework: .flutter(version: "1.0.0"))
        defer { rum.shutdown() }

        XCTAssertFalse(rum.shouldEmitUserActionSpan,
                       "Hybrid (Flutter) must not emit native user action spans to avoid duplicates with setUserInteraction")
    }

    func testShouldEmitUserActionSpan_hybridReactNative_userActionsDisabled_returnsFalse() {
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
            sessionSampleRate: 100,
            instrumentations: [.userActions: false],
            debug: false
        )
        let rum = CoralogixRum(options: options, sdkFramework: .reactNative(version: "2.0.0"))
        defer { rum.shutdown() }

        XCTAssertFalse(rum.shouldEmitUserActionSpan,
                       "Hybrid (React Native) with userActions off must not emit native spans")
    }

    // MARK: - Initialization: hybrid still gets touch swizzles

    /// In hybrid mode we now call initializeUserActionsInstrumentation so that native touch
    /// events are observed. This test only verifies the SDK initializes without crashing
    /// when in hybrid mode (swizzles are installed); shouldEmitUserActionSpan is false so no duplicate spans.
    func testHybridMode_initializesUserActionsInstrumentation() {
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
            sessionSampleRate: 100,
            instrumentations: [.userActions: true],
            debug: false
        )
        let rum = CoralogixRum(options: options, sdkFramework: .flutter(version: "1.0.0"))
        defer { rum.shutdown() }

        XCTAssertTrue(CoralogixRum.isInitialized)
        XCTAssertFalse(rum.shouldEmitUserActionSpan,
                       "Hybrid must not emit native spans even though swizzles are installed for SR")
    }
}
