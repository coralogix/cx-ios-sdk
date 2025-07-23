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
    
    func testExactMatchURL() {
         let url = "https://jsonplaceholder.typicode.com/posts"
         let patterns = ["https://jsonplaceholder.typicode.com/posts"]

         let result = Global.isURLMatchesRegexPattern(string: url, regexs: patterns)
         XCTAssertTrue(result, "Expected exact match to succeed.")
     }

     func testRegexMatchWithPostsPath() {
         let url = "https://jsonplaceholder.typicode.com/posts/1"
         let patterns = [#".*/posts(/\d+)?(\?.*?)?"#]

         let result = Global.isURLMatchesRegexPattern(string: url, regexs: patterns)
         XCTAssertTrue(result, "Expected regex to match /posts/1 path.")
     }

     func testRegexMatchWithQueryString() {
         let url = "https://jsonplaceholder.typicode.com/posts/123?userId=4"
         let patterns = [#".*/posts(/\d+)?(\?.*?)?"#]

         let result = Global.isURLMatchesRegexPattern(string: url, regexs: patterns)
         XCTAssertTrue(result, "Expected regex to match /posts/123?userId=4.")
     }

     func testNoMatchWithOtherPath() {
         let url = "https://jsonplaceholder.typicode.com/comments"
         let patterns = [#".*/posts(/\d+)?(\?.*?)?"#]

         let result = Global.isURLMatchesRegexPattern(string: url, regexs: patterns)
         XCTAssertFalse(result, "Expected no match for unrelated path.")
     }

     func testInvalidRegexIsHandled() {
         let url = "https://jsonplaceholder.typicode.com/posts"
         let patterns = ["[unclosed(regex"] // Invalid pattern

         let result = Global.isURLMatchesRegexPattern(string: url, regexs: patterns)
         XCTAssertFalse(result, "Expected result to be false on invalid regex.")
     }

     func testInvalidURLInputReturnsFalse() {
         let url = "invalid-url"
         let patterns = [#".*/posts(/\d+)?(\?.*?)?"#]

         let result = Global.isURLMatchesRegexPattern(string: url, regexs: patterns)
         XCTAssertFalse(result, "Expected result to be false on invalid URL input.")
     }
}
