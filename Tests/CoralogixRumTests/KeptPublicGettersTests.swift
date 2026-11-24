//
//  KeptPublicGettersTests.swift
//  Coralogix-Rum-Tests
//
//  Compile guard: the session getters below are customer-visible API. This file imports the
//  module WITHOUT `@testable`, so it stops compiling if any of them loses `public` or changes
//  its signature. Behaviour is pinned in `RumWithoutReplayTests`.
//

import XCTest
import Foundation
import Coralogix

final class KeptPublicGettersTests: XCTestCase {

    func testSessionGetters_arePublicWithTheirSignatures() {
        let getSessionID: (CoralogixRum) -> () -> String = CoralogixRum.getSessionID
        let getSessionCreationTimestamp: (CoralogixRum) -> () -> TimeInterval = CoralogixRum.getSessionCreationTimestamp
        let getApplication: (CoralogixRum) -> () -> String = CoralogixRum.getApplication
        let getCoralogixDomain: (CoralogixRum) -> () -> String = CoralogixRum.getCoralogixDomain
        let getPublicKey: (CoralogixRum) -> () -> String = CoralogixRum.getPublicKey
        let getProxyUrl: (CoralogixRum) -> () -> String = CoralogixRum.getProxyUrl
        let isDebug: (CoralogixRum) -> () -> Bool = CoralogixRum.isDebug
        let isIdle: (CoralogixRum) -> () -> Bool = CoralogixRum.isIdle
        let isSessionSampledIn: (CoralogixRum) -> () -> Bool = CoralogixRum.isSessionSampledIn

        let named: [Any] = [getSessionID, getSessionCreationTimestamp, getApplication, getCoralogixDomain,
                            getPublicKey, getProxyUrl, isDebug, isIdle, isSessionSampledIn]
        XCTAssertEqual(named.count, 9)
    }
}
