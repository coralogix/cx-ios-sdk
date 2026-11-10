//
//  NetworkSeverityTests.swift
//  CoralogixRumTests
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class NetworkSeverityTests: XCTestCase {

    func test_successAndRedirectCodes_areInfo() {
        for code in [100, 200, 204, 301, 304, 399] {
            XCTAssertEqual(CoralogixRum.severity(forHttpStatusCode: code), .info, "status \(code)")
        }
    }

    func test_clientAndServerErrorCodes_areError() {
        for code in [400, 401, 404, 499, 500, 503, 599] {
            XCTAssertEqual(CoralogixRum.severity(forHttpStatusCode: code), .error, "status \(code)")
        }
    }
}
