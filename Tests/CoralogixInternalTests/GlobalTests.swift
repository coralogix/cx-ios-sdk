//
//  GlobalTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 25/06/2025.
//

import XCTest
@testable import CoralogixInternal

final class GlobalTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testContainsMonitoredPathReturnsTrueWhenPathIsPresent() {
        let urlString = "http://127.0.0.1:8888?cxforward=https://ingress.staging.rum-ingress-coralogix.com/browser/v1beta/logs"
        XCTAssertTrue(Global.containsMonitoredPath(urlString))
    }
    
    func testContainsMonitoredPathReturnsFalseWhenNoMonitoredPathPresent() {
        let urlString = "http://127.0.0.1:8888?cxforward=https://some.other.url/notmonitored"
        XCTAssertFalse(Global.containsMonitoredPath(urlString))
    }
    
    func testContainsMonitoredPathReturnsTrueWithAlphaSessionRecordingPath() {
        let urlString = "https://example.com/browser/alpha/sessionrecording?param=value"
        XCTAssertTrue(Global.containsMonitoredPath(urlString))
    }
    
    func testContainsMonitoredPathReturnsFalseWithEmptyString() {
        let urlString = ""
        XCTAssertFalse(Global.containsMonitoredPath(urlString))
    }
}
