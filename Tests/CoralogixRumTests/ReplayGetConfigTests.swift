//
//  ReplayGetConfigTests.swift
//
//  The public getter the session-replay wrapper reads its upload settings from on every upload.
//  The wrapper holds no RUM instance, so the getter is static, like the bus entry points.
//
//  SANCTIONED SYMBOL (the only new one this file needs):
//    public static func CoralogixRum.getConfig() -> CoralogixExporterOptions?
//        The LIVE instance's options — the instance initialized while none was live (CX-71257) — read under the
//        live-instance lock. Live: later changes such as `setApplicationContext` are reflected.
//        nil before any init and after shutdown. No instance variant.
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
        // An instance another test left running would still be the live one: one init + shutdown clears it.
        CoralogixRum(options: Self.options(application: "Reset")).shutdown()
    }

    override func tearDown() {
        rums.forEach { $0.shutdown() }
        rums = []
        CoralogixRum.isInitialized = false
        super.tearDown()
    }

    /// RED-now. Before any init there is no config.
    func testGetConfig_beforeInit_isNil() {
        XCTAssertFalse(CoralogixRum.isInitialized, "fixture: not initialized")
        XCTAssertNil(CoralogixRum.getConfig())
    }

    /// RED-now. After init: the options RUM was started with.
    func testGetConfig_afterInit_returnsTheInitOptions() throws {
        start(Self.options(application: "First", key: "key-1", domain: .EU2, proxy: "https://proxy.one"))
        let config = try XCTUnwrap(CoralogixRum.getConfig())
        XCTAssertEqual(config.application, "First")
        XCTAssertEqual(config.publicKey, "key-1")
        XCTAssertEqual(config.coralogixDomain, .EU2)
        XCTAssertEqual(config.proxyUrl, "https://proxy.one")
    }

    /// RED-now. A re-init after shutdown is reflected.
    func testGetConfig_afterReinitWithShutdown_returnsTheNewOptions() throws {
        start(Self.options(application: "First", key: "key-1", domain: .EU2)).shutdown()
        start(Self.options(application: "Second", key: "key-2", domain: .US2, proxy: "https://proxy.two"))
        try Self.assertSecond(CoralogixRum.getConfig())
    }

    /// CX-71257 (reverses the CX-71255 assertion, human ruling 2026-11-25): a re-init over a running
    /// instance is ignored, as on Android — the first instance's options stay.
    func testGetConfig_afterReinitWithoutShutdown_keepsTheFirstOptions() throws {
        start(Self.options(application: "First", key: "key-1", domain: .EU2))
        start(Self.options(application: "Second", key: "key-2", domain: .US2, proxy: "https://proxy.two"))
        let config = try XCTUnwrap(CoralogixRum.getConfig())
        XCTAssertEqual(config.application, "First")
        XCTAssertEqual(config.publicKey, "key-1")
        XCTAssertEqual(config.coralogixDomain, .EU2)
        XCTAssertNil(config.proxyUrl)
    }

    /// RED-now. Live, not a copy taken at init: a later application change is reflected.
    func testGetConfig_reflectsALaterApplicationChange() throws {
        let rum = start(Self.options(application: "First", key: "key-1", domain: .EU2))
        rum.setApplicationContext(application: "Renamed", version: "2.0")
        XCTAssertEqual(try XCTUnwrap(CoralogixRum.getConfig()).application, "Renamed")
    }

    /// RED-now. After shutdown there is no config.
    func testGetConfig_afterShutdown_isNil() {
        let rum = start(Self.options(application: "First", key: "key-1", domain: .EU2))
        XCTAssertNotNil(CoralogixRum.getConfig(), "fixture: initialized")
        rum.shutdown()
        XCTAssertNil(CoralogixRum.getConfig())
    }

    @discardableResult
    private func start(_ options: CoralogixExporterOptions) -> CoralogixRum {
        let rum = CoralogixRum(options: options, sessionManager: SessionManager(snapshotStore: SessionSnapshotStore()))
        rums.append(rum)
        return rum
    }

    private static func assertSecond(_ config: CoralogixExporterOptions?,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let config = try XCTUnwrap(config, file: file, line: line)
        XCTAssertEqual(config.application, "Second", file: file, line: line)
        XCTAssertEqual(config.publicKey, "key-2", file: file, line: line)
        XCTAssertEqual(config.coralogixDomain, .US2, file: file, line: line)
        XCTAssertEqual(config.proxyUrl, "https://proxy.two", file: file, line: line)
    }

    private static func options(application: String, key: String = "test-key",
                                domain: CoralogixDomain = .US2, proxy: String? = nil) -> CoralogixExporterOptions {
        CoralogixExporterOptions(coralogixDomain: domain, environment: "test", application: application,
                                 version: "1.0", publicKey: key, proxyUrl: proxy)
    }
}
