//
//  InstrumentationDataTests.swift
//
//
//  Created by Coralogix Dev Team on 01/08/2024.
//

import XCTest
import Foundation
import CoralogixInternal
@testable import Coralogix

final class InstrumentationDataTests: XCTestCase {
    var mockSpan: SpanDataProtocol!
    var startTime: Date!
    var endTime: Date!

    override func setUpWithError() throws {
        startTime = Date()
        endTime = Date()

        mockSpan = MockSpanData(
            attributes: [
                Keys.severity.rawValue: AttributeValue("3"),
                Keys.eventType.rawValue: AttributeValue(CoralogixEventType.networkRequest.rawValue),
                Keys.source.rawValue: AttributeValue("fetch"),
                Keys.environment.rawValue: AttributeValue("PROD"),
                Keys.userId.rawValue: AttributeValue("12345"),
                Keys.userName.rawValue: AttributeValue("John Doe"),
                Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                Keys.sessionId.rawValue: AttributeValue("session_001"),
                Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
                SemanticAttributes.httpUrl.rawValue: AttributeValue("https://example.com/api"),
                SemanticAttributes.httpMethod.rawValue: AttributeValue("GET"),
                SemanticAttributes.httpStatusCode.rawValue: AttributeValue("200"),
                SemanticAttributes.httpTarget.rawValue: AttributeValue("/api")
            ],
            startTime: startTime,
            endTime: endTime,
            spanId: "span123",
            traceId: "trace123",
            name: "testSpan",
            kind: 1,
            statusCode: ["status": "ok"],
            resources: [
                "a": AttributeValue("1"),
                "b": AttributeValue("2"),
                "c": AttributeValue("3")
            ]
        )
    }

    override func tearDownWithError() throws {
        mockSpan = nil
    }

    // MARK: - Structural tests

    func testInstrumentationDataInitialization() throws {
        let cxRum = makeCxRum()
        let instrumentationData = InstrumentationData(otel: mockSpan, cxRum: cxRum, viewManager: nil)
        XCTAssertNotNil(instrumentationData)
        XCTAssertNotNil(instrumentationData.otelSpan)
        XCTAssertNotNil(instrumentationData.otelResource)
    }

    func testGetInstrumentationDataDictionary() {
        let cxRum = makeCxRum()
        let instrumentationData = InstrumentationData(otel: mockSpan, cxRum: cxRum, viewManager: nil)
        let dict = instrumentationData.getDictionary()
        XCTAssertNotNil(dict[Keys.otelSpan.rawValue])
        XCTAssertNotNil(dict[Keys.otelResource.rawValue])
    }

    func testOtelSpanInitialization() throws {
        let cxRum = makeCxRum()
        let otelSpan = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil)

        XCTAssertEqual(otelSpan.spanId, "span123")
        XCTAssertEqual(otelSpan.traceId, "trace123")
        XCTAssertEqual(otelSpan.name, "testSpan")
        XCTAssertEqual(otelSpan.sessionId, "session_001")
        XCTAssertNil(otelSpan.parentSpanId)

        let (integerPart, fractionalPart) = modf(startTime.timeIntervalSince1970)
        XCTAssertEqual(otelSpan.startTime[0], UInt64(integerPart))
        XCTAssertEqual(otelSpan.startTime[1], UInt64((fractionalPart * 1_000_000_000).rounded()))

        let (integerPartEnd, fractionalPartEnd) = modf(endTime.timeIntervalSince1970)
        XCTAssertEqual(otelSpan.endTime[0], UInt64(integerPartEnd))
        XCTAssertEqual(otelSpan.endTime[1], UInt64((fractionalPartEnd * 1_000_000_000).rounded()))

        XCTAssertEqual(otelSpan.status["status"] as? String, "ok")
        XCTAssertEqual(otelSpan.kind, 1)
    }

    func testGetOtelSpanDictionary_coreFields() {
        let cxRum = makeCxRum()
        let otelSpan = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil)
        let dict = otelSpan.getDictionary()

        XCTAssertEqual(dict[Keys.spanId.rawValue] as? String, "span123")
        XCTAssertEqual(dict[Keys.traceId.rawValue] as? String, "trace123")
        XCTAssertEqual(dict[Keys.name.rawValue] as? String, "testSpan")
        XCTAssertEqual(dict[Keys.kind.rawValue] as? Int, 1)
        XCTAssertNotNil(dict[Keys.startTime.rawValue])
        XCTAssertNotNil(dict[Keys.endTime.rawValue])
        XCTAssertNotNil(dict[Keys.status.rawValue])
        XCTAssertNotNil(dict[Keys.duration.rawValue])
        XCTAssertEqual(dict[Keys.keySessionId.rawValue] as? String, "session_001")
        XCTAssertNil(dict[Keys.parentSpanId.rawValue], "parentSpanId should be absent for root spans")

        XCTAssertEqual(dict[Keys.otlpTraceId.rawValue] as? String, "trace123")
        XCTAssertEqual(dict[Keys.otlpSpanId.rawValue] as? String, "span123")
        XCTAssertEqual(dict[Keys.otlpKindString.rawValue] as? String, Keys.otlpSpanKindClient.rawValue)
        XCTAssertNotNil(dict[Keys.otlpStartTimeUnixNano.rawValue] as? String)
        XCTAssertNotNil(dict[Keys.otlpEndTimeUnixNano.rawValue] as? String)
        XCTAssertEqual(
            (dict[Keys.otlpStatus.rawValue] as? [String: Any])?[Keys.code.rawValue] as? String,
            Keys.otlpStatusCodeUnset.rawValue
        )
    }

    func testInitializationWithAttributes() throws {
        let otelResource = OtelResource(otel: mockSpan)
        let elem1 = try XCTUnwrap(otelResource.attributes["a"] as? AttributeValue, "attribute 'a' should be an AttributeValue")
        XCTAssertEqual(elem1.description, "1")
        let elem2 = try XCTUnwrap(otelResource.attributes["b"] as? AttributeValue, "attribute 'b' should be an AttributeValue")
        XCTAssertEqual(elem2.description, "2")
    }

    func testInitializationWithEmptyAttributes() {
        let emptySpan = MockSpanData(attributes: [:])
        let otelResource = OtelResource(otel: emptySpan)
        XCTAssertTrue(otelResource.attributes.isEmpty)
    }

    func testGetOtelResourceDictionary() {
        let otelResource = OtelResource(otel: mockSpan)
        let dict = otelResource.getDictionary()
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict.count, 1)
        if let attributes = dict[Keys.attributes.rawValue] as? [String: Any] {
            XCTAssertNotNil(attributes)
            XCTAssertEqual(attributes.count, 3)
        } else {
            XCTFail("Missing resources")
        }
    }

    // MARK: - cx_rum.* structured attributes

    func testBuildRumContextAttributes_coreKeys_arePresent() {
        let cxRum = makeCxRum(environment: "staging", appName: "MyApp", appVersion: "3.1.0")
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertNotNil(attrs["cx_rum.mobile_sdk.version"])
        XCTAssertEqual(attrs["cx_rum.environment"] as? String, "staging")
        XCTAssertNotNil(attrs["cx_rum.platform"])
        XCTAssertEqual(attrs["cx_rum.version_metadata.app_name"] as? String, "MyApp")
        XCTAssertEqual(attrs["cx_rum.version_metadata.app_version"] as? String, "3.1.0")
    }

    func testBuildRumContextAttributes_emptyEnvironment_isOmitted() {
        let cxRum = makeCxRum(environment: "")
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertNil(attrs["cx_rum.environment"])
    }

    func testBuildRumContextAttributes_sessionContext_isPresent() {
        let cxRum = makeCxRum(userId: "u-42", userName: "Alice", userEmail: "alice@test.com", sessionId: "sess-xyz")
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertEqual(attrs["cx_rum.session_context.session_id"] as? String, "sess-xyz")
        XCTAssertEqual(attrs["cx_rum.session_context.user_id"] as? String, "u-42")
        XCTAssertEqual(attrs["cx_rum.session_context.user_name"] as? String, "Alice")
        XCTAssertEqual(attrs["cx_rum.session_context.user_email"] as? String, "alice@test.com")
        XCTAssertNotNil(attrs["cx_rum.session_context.os"])
        XCTAssertNotNil(attrs["cx_rum.session_context.osVersion"])
        XCTAssertNotNil(attrs["cx_rum.session_context.device"])
        XCTAssertNotNil(attrs["cx_rum.session_context.user_agent"])
    }

    func testBuildRumContextAttributes_eventContext_isPresent() {
        let cxRum = makeCxRum(eventType: .networkRequest, severity: 3, source: "fetch")
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertEqual(attrs["cx_rum.event_context.type"] as? String, CoralogixEventType.networkRequest.rawValue)
        XCTAssertEqual(attrs["cx_rum.event_context.severity"] as? Int, 3)
        XCTAssertEqual(attrs["cx_rum.event_context.source"] as? String, "fetch")
    }

    func testBuildRumContextAttributes_networkRequestContext_presentForNetworkEvent() {
        let cxRum = makeCxRum(
            eventType: .networkRequest,
            url: "https://api.example.com/users",
            method: "POST",
            statusCode: 201,
            fragments: "/users"
        )
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertEqual(attrs["cx_rum.network_request_context.url"] as? String, "https://api.example.com/users")
        XCTAssertEqual(attrs["cx_rum.network_request_context.method"] as? String, "POST")
        XCTAssertEqual(attrs["cx_rum.network_request_context.status_code"] as? Int, 201)
        XCTAssertEqual(attrs["cx_rum.network_request_context.fragments"] as? String, "/users")
        XCTAssertNotNil(attrs["cx_rum.network_request_context.status_text"])
    }

    func testBuildRumContextAttributes_networkRequestContext_absentForNonNetworkEvent() {
        let cxRum = makeCxRum(eventType: .log)
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertNil(attrs["cx_rum.network_request_context.url"])
        XCTAssertNil(attrs["cx_rum.network_request_context.method"])
        XCTAssertNil(attrs["cx_rum.network_request_context.status_code"])
        XCTAssertNil(attrs["cx_rum.network_request_context.fragments"])
    }

    func testBuildRumContextAttributes_labels_areNestedUnderSingleKey() {
        let labels: [String: Any] = ["team": "mobile", "env": "staging"]
        let cxRum = makeCxRum(labels: labels)
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        let labelsDict = attrs["cx_rum.labels"] as? [String: Any]
        XCTAssertNotNil(labelsDict, "cx_rum.labels must be a nested dictionary, not flattened")
        XCTAssertEqual(labelsDict?["team"] as? String, "mobile")
        XCTAssertEqual(labelsDict?["env"] as? String, "staging")
        // Ensure no flattened keys exist
        XCTAssertNil(attrs["cx_rum.labels.team"])
        XCTAssertNil(attrs["cx_rum.labels.env"])
    }

    func testBuildRumContextAttributes_nilLabels_areOmitted() {
        let cxRum = makeCxRum(labels: nil)
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertNil(attrs["cx_rum.labels"])
    }

    func testBuildRumContextAttributes_emptyLabels_areOmitted() {
        let cxRum = makeCxRum(labels: [:])
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertNil(attrs["cx_rum.labels"])
    }

    func testBuildRumContextAttributes_pageContext_fromViewManager() {
        let viewManager = MockViewManager(keyChain: KeychainManager())
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "HomeViewController"))
        let cxRum = makeCxRum()
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: viewManager).attributes

        XCTAssertEqual(attrs["cx_rum.page_context.page_url"] as? String, "HomeViewController")
        XCTAssertEqual(attrs["cx_rum.page_context.page_fragments"] as? String, "HomeViewController")
    }

    func testBuildRumContextAttributes_pageContext_absentWhenNoView() {
        let cxRum = makeCxRum()
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertNil(attrs["cx_rum.page_context.page_url"])
        XCTAssertNil(attrs["cx_rum.page_context.page_fragments"])
    }

    func testBuildRumContextAttributes_pageContext_absentWhenViewManagerHasNoActiveView() {
        // ViewManager with no view set returns ["view": ""] — page context must still be omitted
        let emptyViewManager = MockViewManager(keyChain: KeychainManager())
        let cxRum = makeCxRum()
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: emptyViewManager).attributes

        XCTAssertNil(attrs["cx_rum.page_context.page_url"])
        XCTAssertNil(attrs["cx_rum.page_context.page_fragments"])
    }

    func testBuildRumContextAttributes_errorContext_presentWhenNonEmpty() {
        let cxRum = makeCxRum(errorType: "NSURLError", errorMessage: "Connection timed out")
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertEqual(attrs["cx_rum.error_context.error_type"] as? String, "NSURLError")
        XCTAssertEqual(attrs["cx_rum.error_context.error_message"] as? String, "Connection timed out")
    }

    func testBuildRumContextAttributes_errorContext_absentWhenEmpty() {
        let cxRum = makeCxRum(errorType: "", errorMessage: "")
        let attrs = OtelSpan(otel: mockSpan, cxRum: cxRum, viewManager: nil).attributes

        XCTAssertNil(attrs["cx_rum.error_context.error_type"])
        XCTAssertNil(attrs["cx_rum.error_context.error_message"])
    }

    // MARK: - Helpers

    private func makeCxRum(
        environment: String = "PROD",
        appName: String = "TestApp",
        appVersion: String = "1.0.0",
        eventType: CoralogixEventType = .networkRequest,
        severity: Int = 3,
        source: String = "fetch",
        userId: String = "user_001",
        userName: String = "Test User",
        userEmail: String = "test@example.com",
        sessionId: String = "session_001",
        url: String = "https://example.com/api",
        method: String = "GET",
        statusCode: Int = 200,
        fragments: String = "/api",
        labels: [String: Any]? = nil,
        errorType: String = "",
        errorMessage: String = ""
    ) -> CxRum {
        let eventSpan = MockSpanData(attributes: [
            Keys.eventType.rawValue: AttributeValue(eventType.rawValue),
            Keys.source.rawValue: AttributeValue(source),
            Keys.severity.rawValue: AttributeValue("\(severity)")
        ])

        let sessionSpan = MockSpanData(attributes: [
            Keys.sessionId.rawValue: AttributeValue(sessionId),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
            Keys.userId.rawValue: AttributeValue(userId),
            Keys.userName.rawValue: AttributeValue(userName),
            Keys.userEmail.rawValue: AttributeValue(userEmail)
        ])

        let networkSpan = MockSpanData(attributes: [
            SemanticAttributes.httpUrl.rawValue: AttributeValue(url),
            SemanticAttributes.httpMethod.rawValue: AttributeValue(method),
            SemanticAttributes.httpStatusCode.rawValue: AttributeValue("\(statusCode)"),
            SemanticAttributes.httpTarget.rawValue: AttributeValue(fragments),
            SemanticAttributes.httpScheme.rawValue: AttributeValue("https"),
            SemanticAttributes.netPeerName.rawValue: AttributeValue("example.com")
        ])

        let errorSpan = MockSpanData(attributes: [
            Keys.errorType.rawValue: AttributeValue(errorType),
            Keys.errorMessage.rawValue: AttributeValue(errorMessage)
        ])

        let emptySpan = MockSpanData(attributes: [:])

        return CxRum(
            timeStamp: Date().timeIntervalSince1970,
            networkRequestContext: NetworkRequestContext(otel: networkSpan),
            versionMetadata: VersionMetadata(appName: appName, appVersion: appVersion),
            sessionContext: SessionContext(otel: sessionSpan, userMetadata: nil),
            prevSessionContext: nil,
            eventContext: EventContext(otel: eventSpan),
            logContext: LogContext(otel: emptySpan),
            mobileSDK: MobileSDK(sdkFramework: .swift),
            environment: environment,
            traceId: "trace-test",
            spanId: "span-test",
            errorContext: ErrorContext(otel: errorSpan),
            deviceContext: DeviceContext(otel: emptySpan),
            deviceState: DeviceState(networkManager: MockNetworkManager()),
            labels: labels,
            snapshotContext: nil,
            interactionContext: nil,
            mobileVitalsContext: nil,
            lifeCycleContext: nil,
            screenShotContext: nil,
            internalContext: nil,
            measurementContext: nil,
            fingerPrint: "test-fingerprint"
        )
    }
}
