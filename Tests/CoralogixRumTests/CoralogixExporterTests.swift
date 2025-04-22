//
//  CoralogixExporterTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 16/03/2025.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class CoralogixExporterTests: XCTestCase {
    
    var coralogixExporter: CoralogixExporter!
    var options: CoralogixExporterOptions?
    var mockSpan: SpanDataProtocol!
    var statTime: Date!
    var endTime: Date!
    let labels = ["label1": "value1"]
    
    override func setUp() {
        super.setUp()
        statTime = Date()
        endTime = Date()
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [], //[".*\\.il$", "https://www.coralogix.com/academy"],
                                           ignoreErrors: [], //[".*errorcode=.*", "Im cusom Error"],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        coralogixExporter = coralogixRum.coralogixExporter
        
    }
    
    func test_shouldRemoveSpan_whenURLIsNil_returnsTrue() {
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        
        XCTAssertTrue(coralogixExporter.shouldRemoveSpan(span: mockSpan))
    }
    
    func test_shouldRemoveSpan_whenURLMatchesEndPoint_returnsFalse() {
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             SemanticAttributes.httpUrl.rawValue: AttributeValue("https://ingress.us2.rum-ingress-coralogix.com/browser/v1beta/logs")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        
        XCTAssertFalse(coralogixExporter.shouldRemoveSpan(span: mockSpan))
    }
    
    func test_shouldRemoveSpan_whenURLDifferentAndIgnoreUrlsNil_returnsTrue() {
        //coralogixExporter.options.ignoreUrls = nil
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             SemanticAttributes.httpUrl.rawValue: AttributeValue("https://coralogix.com")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        
        XCTAssertTrue(coralogixExporter.shouldRemoveSpan(span: mockSpan))
    }
    
    func test_shouldRemoveSpan_whenURLInIgnoreUrls_returnsFalse() {
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: ["https://ignore.com"],
                                           ignoreErrors: [],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        coralogixExporter = coralogixRum.coralogixExporter
        
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             SemanticAttributes.httpUrl.rawValue: AttributeValue("https://ignore.com")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        
        XCTAssertFalse(coralogixExporter.shouldRemoveSpan(span: mockSpan))
    }
    
    func test_shouldRemoveSpan_whenURLMatchesRegexInIgnoreUrls_returnsFalse() {        
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: ["ignore\\.com"],
                                           ignoreErrors: [],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        coralogixExporter = coralogixRum.coralogixExporter
        
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             SemanticAttributes.httpUrl.rawValue: AttributeValue("https://ignore.com")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        XCTAssertFalse(coralogixExporter.shouldRemoveSpan(span: mockSpan))
    }

    func test_shouldRemoveSpan_whenURLDoesNotMatchRegexInIgnoreUrls_returnsTrue() {
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: ["patternthatdoesnotmatch"],
                                           ignoreErrors: [],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        coralogixExporter = coralogixRum.coralogixExporter
        
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             SemanticAttributes.httpUrl.rawValue: AttributeValue("https://no-match.com")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        XCTAssertTrue(coralogixExporter.shouldRemoveSpan(span: mockSpan))
    }
    
    func test_shouldRemoveSpan_whenIgnoreUrlsEmpty_returnsTrue() {
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [],
                                           ignoreErrors: [],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        coralogixExporter = coralogixRum.coralogixExporter
        
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             SemanticAttributes.httpUrl.rawValue: AttributeValue("https://any.com")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        XCTAssertTrue(coralogixExporter.shouldRemoveSpan(span: mockSpan))
    }
    
    func testShouldFilterIgnoreError_noErrorMessage_returnsTrue() {
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [],
                                           ignoreErrors: [],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        coralogixExporter = coralogixRum.coralogixExporter
        
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             SemanticAttributes.httpUrl.rawValue: AttributeValue("https://any.com")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        let result = coralogixExporter.shouldFilterIgnoreError(span: mockSpan)
        XCTAssertTrue(result)
    }
    
    func testShouldFilterIgnoreError_messageInIgnoreList_returnsFalse() {
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [],
                                           ignoreErrors: ["IgnoreThisError"],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        coralogixExporter = coralogixRum.coralogixExporter
        
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.errorMessage.rawValue: AttributeValue("IgnoreThisError"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             SemanticAttributes.httpUrl.rawValue: AttributeValue("https://any.com")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        let result = coralogixExporter.shouldFilterIgnoreError(span: mockSpan)
        XCTAssertFalse(result)
    }

    func testShouldFilterIgnoreError_messageMatchesRegex_returnsFalse() {
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [],
                                           ignoreErrors: [#"\b\w*regex\w*\b"#],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        coralogixExporter = coralogixRum.coralogixExporter
        
        mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                             Keys.eventType.rawValue: AttributeValue("log"),
                                             Keys.source.rawValue: AttributeValue("console"),
                                             Keys.environment.rawValue: AttributeValue("prod"),
                                             Keys.userId.rawValue: AttributeValue("12345"),
                                             Keys.userName.rawValue: AttributeValue("John Doe"),
                                             Keys.errorMessage.rawValue: AttributeValue("SomethingRegexErrorTriggered"),
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             SemanticAttributes.httpUrl.rawValue: AttributeValue("https://any.com")],
                                startTime: statTime, endTime: endTime, spanId: "span123",
                                traceId: "trace123", name: "testSpan", kind: 1,
                                statusCode: ["status": "ok"],
                                resources: ["a": AttributeValue("1"),
                                            "b": AttributeValue("2"),
                                            "c": AttributeValue("3")])
        let result = coralogixExporter.shouldFilterIgnoreError(span: mockSpan)
        XCTAssertFalse(result)
    }

    func testShouldFilterIgnoreError_messageNotMatched_returnsTrue() {
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                                   userContext: nil,
                                                   environment: "PROD",
                                                   application: "TestApp-iOS",
                                                   version: "1.0",
                                                   publicKey: "token",
                                                   ignoreUrls: [],
                                                   ignoreErrors: [],
                                                   labels: ["item" : "banana", "itemPrice" : 1000],
                                                   sampleRate: 100,
                                                   debug: true)
                let coralogixRum = CoralogixRum(options: options!)
                coralogixExporter = coralogixRum.coralogixExporter
                
                mockSpan = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                     Keys.eventType.rawValue: AttributeValue("log"),
                                                     Keys.source.rawValue: AttributeValue("console"),
                                                     Keys.environment.rawValue: AttributeValue("prod"),
                                                     Keys.userId.rawValue: AttributeValue("12345"),
                                                     Keys.userName.rawValue: AttributeValue("John Doe"),
                                                     Keys.errorMessage.rawValue: AttributeValue("SomeOtherError"),
                                                     Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                                     SemanticAttributes.httpUrl.rawValue: AttributeValue("https://any.com")],
                                        startTime: statTime, endTime: endTime, spanId: "span123",
                                        traceId: "trace123", name: "testSpan", kind: 1,
                                        statusCode: ["status": "ok"],
                                        resources: ["a": AttributeValue("1"),
                                                    "b": AttributeValue("2"),
                                                    "c": AttributeValue("3")])
        let result = coralogixExporter.shouldFilterIgnoreError(span: mockSpan)
        XCTAssertTrue(result)
    }


    override func tearDown() {
        super.tearDown()
    }
}
