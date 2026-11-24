//
//  ReplayGetConfigTests.swift
//
//  The public getter the session-replay wrapper reads its upload settings from on every upload.
//
//  SANCTIONED SYMBOL (the only new one this file needs):
//    public func CoralogixRum.getConfig() -> CoralogixExporterOptions?
//        The LIVE options (domain, public key, proxy, application and the rest, including later
//        changes such as `setApplicationContext`); nil while this instance is not initialized:
//        before its startup completed and after `shutdown()`.
//
//  Until the symbol exists this file does not compile: that is its RED state. Every test is RED-now
//  (compile); with a bare stub returning nil, all but the before-init test fail by assertion.
//

import XCTest
@testable import Coralogix

final class ReplayGetConfigTests: XCTestCase {

    private var rums: [CoralogixRum] = []

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
    }

    override func tearDown() {
        rums.forEach { $0.shutdown() }
        rums = []
        CoralogixRum.isInitialized = false
        super.tearDown()
    }

    /// RED-now. An instance whose startup never ran (no session manager) has no config.
    func testGetConfig_beforeInit_isNil() {
        let rum = CoralogixRum(options: Self.options(application: "Never"), sessionManager: nil)
        rums.append(rum)
        XCTAssertFalse(CoralogixRum.isInitialized, "fixture: not initialized")
        XCTAssertNil(rum.getConfig())
    }

    /// RED-now. After init: the options RUM was started with.
    func testGetConfig_afterInit_returnsTheInitOptions() throws {
        let rum = start(Self.options(application: "First", key: "key-1", domain: .EU2, proxy: "https://proxy.one"))
        let config = try XCTUnwrap(rum.getConfig())
        XCTAssertEqual(config.application, "First")
        XCTAssertEqual(config.publicKey, "key-1")
        XCTAssertEqual(config.coralogixDomain, .EU2)
        XCTAssertEqual(config.proxyUrl, "https://proxy.one")
    }

    /// RED-now. A re-init is reflected: the new instance answers with the new options.
    func testGetConfig_afterReinit_returnsTheNewOptions() throws {
        let first = start(Self.options(application: "First", key: "key-1", domain: .EU2, proxy: nil))
        first.shutdown()
        let second = start(Self.options(application: "Second", key: "key-2", domain: .US2, proxy: "https://proxy.two"))
        let config = try XCTUnwrap(second.getConfig())
        XCTAssertEqual(config.application, "Second")
        XCTAssertEqual(config.publicKey, "key-2")
        XCTAssertEqual(config.coralogixDomain, .US2)
        XCTAssertEqual(config.proxyUrl, "https://proxy.two")
    }

    /// RED-now. Live, not a copy taken at init: a later application change is reflected.
    func testGetConfig_reflectsALaterApplicationChange() throws {
        let rum = start(Self.options(application: "First", key: "key-1", domain: .EU2, proxy: nil))
        rum.setApplicationContext(application: "Renamed", version: "2.0")
        XCTAssertEqual(try XCTUnwrap(rum.getConfig()).application, "Renamed")
    }

    /// RED-now. After shutdown there is no config.
    func testGetConfig_afterShutdown_isNil() {
        let rum = start(Self.options(application: "First", key: "key-1", domain: .EU2, proxy: nil))
        XCTAssertNotNil(rum.getConfig(), "fixture: initialized")
        rum.shutdown()
        XCTAssertNil(rum.getConfig())
    }

    private func start(_ options: CoralogixExporterOptions) -> CoralogixRum {
        let rum = CoralogixRum(options: options, sessionManager: SessionManager(snapshotStore: SessionSnapshotStore()))
        rums.append(rum)
        return rum
    }

    private static func options(application: String, key: String = "test-key",
                                domain: CoralogixDomain = .US2, proxy: String? = nil) -> CoralogixExporterOptions {
        CoralogixExporterOptions(coralogixDomain: domain, environment: "test", application: application,
                                 version: "1.0", publicKey: key, proxyUrl: proxy)
    }
}
