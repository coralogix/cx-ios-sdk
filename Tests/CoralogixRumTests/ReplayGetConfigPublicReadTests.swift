//
//  ReplayGetConfigPublicReadTests.swift
//
//  The session-replay wrapper is a separate module: it reads its upload settings through the PUBLIC surface of
//  `CoralogixRum.getConfig()` — domain, public key, application and proxy URL — on every upload. Plain `import`
//  (no `@testable`) on purpose: this file compiles only while those four are readable from outside the module,
//  matching Android's `CoralogixOptions` (public read-only `val`s). Read-only to callers: setters stay internal.
//

import XCTest
import Coralogix

final class ReplayGetConfigPublicReadTests: XCTestCase {

    func testGetConfig_exposesTheFourReplayUploadSettings_toAnotherModule() {
        let options = CoralogixExporterOptions(coralogixDomain: .EU2, environment: "test", application: "replay-app",
                                               version: "1.0", publicKey: "replay-key",
                                               proxyUrl: "https://proxy.example.com/rum")
        let rum = CoralogixRum(options: options)
        defer { rum.shutdown() }

        guard let config = CoralogixRum.getConfig() else { return XCTFail("getConfig() is live after init") }
        XCTAssertEqual(config.coralogixDomain, .EU2)
        XCTAssertEqual(config.coralogixDomain.rawValue, CoralogixDomain.EU2.rawValue)
        XCTAssertEqual(config.publicKey, "replay-key")
        XCTAssertEqual(config.application, "replay-app")
        XCTAssertEqual(config.proxyUrl, "https://proxy.example.com/rum")
    }
}
