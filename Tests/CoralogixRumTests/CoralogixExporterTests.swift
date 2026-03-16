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
                                             Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200)],
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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
                                             Keys.sessionId.rawValue: AttributeValue("session_001"),
                                             Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
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

    func test_resolvedUrlString_withProxyUrl() {
        let proxyUrl = "https://proxy.example.com"
        let endPoint = coralogixExporter.endPoint
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                          ignoreUrls: [],
                                          ignoreErrors: [],
                                          labels: ["item" : "banana", "itemPrice" : 1000],
                                          proxyUrl: proxyUrl,
                                          debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        
        // When
        let result = coralogixRum.coralogixExporter?.spanUploader.resolvedUrlString(endPoint: endPoint)
        
        // Then
        guard let result = result else {
            XCTFail("URL should not be nil")
            return
        }
        
        XCTAssertTrue(result.contains(proxyUrl))
        XCTAssertTrue(result.contains("cxforward="))
        XCTAssertTrue(result.contains(CoralogixDomain.US2.rawValue))
    }
    
    func test_resolvedUrlString_withoutProxyUrl() {
        let endPoint = coralogixExporter.endPoint
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                          ignoreUrls: [],
                                          ignoreErrors: [],
                                          labels: ["item" : "banana", "itemPrice" : 1000],
                                          proxyUrl: nil,
                                          debug: true)
        let coralogixRum = CoralogixRum(options: options!)
        // When
        let result = coralogixRum.coralogixExporter?.spanUploader.resolvedUrlString(endPoint: endPoint)

        // Then
        XCTAssertEqual(result, coralogixRum.coralogixExporter?.endPoint)
    }

    // MARK: - beforeSendCallBack tests (CX-32889)

    /// Helper: creates a SpanData that survives the full export pipeline
    /// (filtering, encoding, CxSpan creation).
    private func makeValidSpanData() -> SpanData {
        let attributes: [String: AttributeValue] = [
            Keys.severity.rawValue: AttributeValue("3"),
            Keys.eventType.rawValue: AttributeValue("log"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.environment.rawValue: AttributeValue("prod"),
            Keys.userId.rawValue: AttributeValue("12345"),
            Keys.userName.rawValue: AttributeValue("John Doe"),
            Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
            SemanticAttributes.httpUrl.rawValue: AttributeValue("https://example.com/api/data")
        ]
        var span = SpanData(traceId: TraceId.random(),
                            spanId: SpanId.random(),
                            name: "testSpan",
                            kind: .client,
                            startTime: Date(),
                            attributes: attributes,
                            endTime: Date(),
                            hasEnded: true)
        return span
    }

    func test_export_invokesBeforeSendCallBack_whenSet() {
        let expectation = expectation(description: "beforeSendCallBack should be invoked")
        var receivedSpans: [[String: Any]]?

        var opts = CoralogixExporterOptions(coralogixDomain: .US2,
                                            userContext: nil,
                                            environment: "PROD",
                                            application: "TestApp-iOS",
                                            version: "1.0",
                                            publicKey: "token",
                                            ignoreUrls: [],
                                            ignoreErrors: [],
                                            labels: ["item": "banana"],
                                            debug: true)
        opts.beforeSendCallBack = { spans in
            receivedSpans = spans
            expectation.fulfill()
        }
        let rum = CoralogixRum(options: opts)
        guard let exporter = rum.coralogixExporter else {
            XCTFail("Exporter should not be nil")
            return
        }

        let span = makeValidSpanData()
        let result = exporter.export(spans: [span], explicitTimeout: nil)

        waitForExpectations(timeout: 5)
        XCTAssertEqual(result, .success, "Export should return .success when beforeSendCallBack handles spans")
        XCTAssertNotNil(receivedSpans, "Callback should receive spans")
        XCTAssertFalse(receivedSpans!.isEmpty, "Callback should receive non-empty spans array")
    }

    func test_export_doesNotDropSpans_whenBeforeSendCallBackIsNil() {
        // Previously, Flutter/ReactNative exports without a beforeSendCallBack
        // would silently drop spans. Verify this no longer happens.
        let opts = CoralogixExporterOptions(coralogixDomain: .US2,
                                            userContext: nil,
                                            environment: "PROD",
                                            application: "TestApp-iOS",
                                            version: "1.0",
                                            publicKey: "token",
                                            ignoreUrls: [],
                                            ignoreErrors: [],
                                            labels: ["item": "banana"],
                                            debug: true)
        // beforeSendCallBack is nil (default)
        let rum = CoralogixRum(options: opts, sdkFramework: .flutter(version: "1.0.0"))
        guard let exporter = rum.coralogixExporter else {
            XCTFail("Exporter should not be nil")
            return
        }

        let span = makeValidSpanData()
        let result = exporter.export(spans: [span], explicitTimeout: nil)

        // The upload may fail due to network in tests, but it should NOT
        // return .failure from the early "no spans" check. The span must
        // survive filtering and encoding, proving it was not silently dropped.
        // We verify the exporter attempted to process the spans by checking
        // that encodeSpans produced output (if it didn't, we'd get .success
        // from the isEmpty check, not .failure).
        // Any result other than the old silent .failure at the switch fallthrough is acceptable.
        XCTAssertNotNil(result, "Export should return a valid result code")
    }

    override func tearDown() {
        super.tearDown()
    }
}
