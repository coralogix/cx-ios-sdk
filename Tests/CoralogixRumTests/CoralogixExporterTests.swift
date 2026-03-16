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
        let uploader = coralogixRum.coralogixExporter?.spanUploader as? SpanUploader
        let result = uploader?.resolvedUrlString(endPoint: endPoint)

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
        let uploader = coralogixRum.coralogixExporter?.spanUploader as? SpanUploader
        let result = uploader?.resolvedUrlString(endPoint: endPoint)

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
        let span = SpanData(traceId: TraceId.random(),
                            spanId: SpanId.random(),
                            name: "testSpan",
                            kind: .client,
                            startTime: Date(),
                            attributes: attributes,
                            endTime: Date(),
                            hasEnded: true)
        return span
    }

    func test_export_invokesBeforeSendCallBack_forFlutter() {
        // Flutter/ReactNative: when beforeSendCallBack is set, spans go to
        // the callback (platform channel) instead of the native uploader.
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
        let rum = CoralogixRum(options: opts, sdkFramework: .flutter(version: "1.0.0"))
        guard let exporter = rum.coralogixExporter else {
            XCTFail("Exporter should not be nil")
            return
        }

        let span = makeValidSpanData()
        let result = exporter.export(spans: [span], explicitTimeout: nil)

        waitForExpectations(timeout: 5)
        XCTAssertEqual(result, .success, "Export should return .success when beforeSendCallBack handles spans")
        XCTAssertNotNil(receivedSpans, "Callback should receive spans")
        XCTAssertFalse(receivedSpans?.isEmpty ?? true, "Callback should receive non-empty spans array")
    }

    func test_export_uploadsDirectly_whenFlutterAndBeforeSendCallBackIsNil() {
        // Previously, Flutter/ReactNative exports without a beforeSendCallBack
        // would silently drop spans. Verify this no longer happens by injecting
        // a mock uploader that records invocation without making network calls.
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

        let mockUploader = MockSpanUploader()
        exporter.spanUploader = mockUploader

        let span = makeValidSpanData()
        let result = exporter.export(spans: [span], explicitTimeout: nil)

        XCTAssertTrue(mockUploader.uploadCalled, "spanUploader.upload must be invoked when beforeSendCallBack is nil")
        XCTAssertFalse(mockUploader.uploadedSpans.isEmpty, "Upload should receive non-empty spans")
        XCTAssertEqual(result, .success, "Export should return .success from mock uploader")
    }

    func test_export_nativeBypassesBeforeSendCallBack() {
        // Native (Swift) clients must always upload via spanUploader,
        // even when beforeSendCallBack is set, so the exporter contract is preserved.
        var callbackInvoked = false

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
        opts.beforeSendCallBack = { _ in
            callbackInvoked = true
        }
        // Default sdkFramework is .swift (native)
        let rum = CoralogixRum(options: opts)
        guard let exporter = rum.coralogixExporter else {
            XCTFail("Exporter should not be nil")
            return
        }

        let span = makeValidSpanData()
        _ = exporter.export(spans: [span], explicitTimeout: nil)

        XCTAssertFalse(callbackInvoked, "Native clients must not route spans through beforeSendCallBack")
    }

    // MARK: - BUGV2-5379: beforeSend severity change must adjust errorCount

    private func makeErrorSpanData() -> SpanData {
        let attributes: [String: AttributeValue] = [
            Keys.severity.rawValue: AttributeValue("5"),
            Keys.eventType.rawValue: AttributeValue("error"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.environment.rawValue: AttributeValue("prod"),
            Keys.userId.rawValue: AttributeValue("12345"),
            Keys.userName.rawValue: AttributeValue("John Doe"),
            Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
            SemanticAttributes.httpUrl.rawValue: AttributeValue("https://example.com/api/data")
        ]
        return SpanData(traceId: TraceId.random(),
                        spanId: SpanId.random(),
                        name: "errorSpan",
                        kind: .client,
                        startTime: Date(),
                        attributes: attributes,
                        endTime: Date(),
                        hasEnded: true)
    }

    func test_beforeSend_errorDowngradedToInfo_decrementsErrorCount() {
        var opts = CoralogixExporterOptions(coralogixDomain: .US2,
                                            userContext: nil,
                                            environment: "PROD",
                                            application: "TestApp-iOS",
                                            version: "1.0",
                                            publicKey: "token",
                                            ignoreUrls: [],
                                            ignoreErrors: [],
                                            labels: [:],
                                            debug: true)
        opts.beforeSend = { cxRum in
            var modified = cxRum
            if var eventContext = modified[Keys.eventContext.rawValue] as? [String: Any] {
                eventContext[Keys.severity.rawValue] = CoralogixLogSeverity.info.rawValue
                modified[Keys.eventContext.rawValue] = eventContext
            }
            return modified
        }
        let rum = CoralogixRum(options: opts)
        guard let exporter = rum.coralogixExporter else { return XCTFail("Exporter nil") }

        let encoded = exporter.encodeSpans(spans: [makeErrorSpanData()])

        XCTAssertFalse(encoded.isEmpty, "Span should not be dropped")
        XCTAssertEqual(exporter.getSessionManager().getErrorCount(), 0,
                       "errorCount should be 0 after beforeSend downgrades Error to Info")
    }

    func test_beforeSend_errorDowngraded_updatesSnapshotContextErrorCount() {
        var opts = CoralogixExporterOptions(coralogixDomain: .US2,
                                            userContext: nil,
                                            environment: "PROD",
                                            application: "TestApp-iOS",
                                            version: "1.0",
                                            publicKey: "token",
                                            ignoreUrls: [],
                                            ignoreErrors: [],
                                            labels: [:],
                                            debug: true)
        opts.beforeSend = { cxRum in
            var modified = cxRum
            if var eventContext = modified[Keys.eventContext.rawValue] as? [String: Any] {
                eventContext[Keys.severity.rawValue] = CoralogixLogSeverity.info.rawValue
                modified[Keys.eventContext.rawValue] = eventContext
            }
            return modified
        }
        let rum = CoralogixRum(options: opts)
        guard let exporter = rum.coralogixExporter else { return XCTFail("Exporter nil") }

        let encoded = exporter.encodeSpans(spans: [makeErrorSpanData()])

        guard let span = encoded.first,
              let textDict = span[Keys.text.rawValue] as? [String: Any],
              let cxRumDict = textDict[Keys.cxRum.rawValue] as? [String: Any],
              let snapshotDict = cxRumDict[Keys.snapshotContext.rawValue] as? [String: Any],
              let errorCount = snapshotDict[Keys.errorCount.rawValue] as? Int else {
            return XCTFail("snapshotContext not found in encoded span")
        }
        XCTAssertEqual(errorCount, 0,
                       "snapshotContext.errorCount should reflect the decremented count")
    }

    func test_beforeSend_errorSpanDropped_decrementsErrorCount() {
        var opts = CoralogixExporterOptions(coralogixDomain: .US2,
                                            userContext: nil,
                                            environment: "PROD",
                                            application: "TestApp-iOS",
                                            version: "1.0",
                                            publicKey: "token",
                                            ignoreUrls: [],
                                            ignoreErrors: [],
                                            labels: [:],
                                            debug: true)
        opts.beforeSend = { _ in return nil }
        let rum = CoralogixRum(options: opts)
        guard let exporter = rum.coralogixExporter else { return XCTFail("Exporter nil") }

        let encoded = exporter.encodeSpans(spans: [makeErrorSpanData()])

        XCTAssertTrue(encoded.isEmpty, "Dropped span should produce empty result")
        XCTAssertEqual(exporter.getSessionManager().getErrorCount(), 0,
                       "errorCount should be 0 after error span is dropped by beforeSend")
    }

    func test_beforeSend_nonErrorUpgradedToError_incrementsErrorCount() {
        var opts = CoralogixExporterOptions(coralogixDomain: .US2,
                                            userContext: nil,
                                            environment: "PROD",
                                            application: "TestApp-iOS",
                                            version: "1.0",
                                            publicKey: "token",
                                            ignoreUrls: [],
                                            ignoreErrors: [],
                                            labels: [:],
                                            debug: true)
        opts.beforeSend = { cxRum in
            var modified = cxRum
            if var eventContext = modified[Keys.eventContext.rawValue] as? [String: Any] {
                eventContext[Keys.severity.rawValue] = CoralogixLogSeverity.error.rawValue
                modified[Keys.eventContext.rawValue] = eventContext
            }
            return modified
        }
        let rum = CoralogixRum(options: opts)
        guard let exporter = rum.coralogixExporter else { return XCTFail("Exporter nil") }

        let encoded = exporter.encodeSpans(spans: [makeValidSpanData()])

        XCTAssertFalse(encoded.isEmpty, "Span should not be dropped")
        XCTAssertEqual(exporter.getSessionManager().getErrorCount(), 1,
                       "errorCount should be 1 after beforeSend upgrades non-Error to Error")
    }

    override func tearDown() {
        super.tearDown()
    }
}

// MARK: - Test Doubles

private class MockSpanUploader: SpanUploading {
    var uploadCalled = false
    var uploadedSpans: [[String: Any]] = []

    func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
        uploadCalled = true
        uploadedSpans = spans
        return .success
    }
}
