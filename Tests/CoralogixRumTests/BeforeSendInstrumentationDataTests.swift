//
//  BeforeSendInstrumentationDataTests.swift
//
//  CX-44686: when `beforeSend` modifies a cx_rum field, the change must propagate
//  to BOTH `text.cx_rum` AND `instrumentation_data.otelSpan.attributes.cx_rum.*`.
//  Read-only / identity / counter / runtime-constant fields must not be exposed
//  in the editable subset, and customer-supplied values for those keys must be
//  ignored even if the callback injects them in its return dict.
//

import XCTest
import CoralogixInternal
import Foundation

@testable import Coralogix

final class BeforeSendInstrumentationDataTests: XCTestCase {

    // MARK: - Fixture

    private var mockSpanData: SpanDataProtocol!
    private var mockVersionMetadata: VersionMetadata!
    private var mockSessionManager: SessionManager!
    private var mockNetworkManager: NetworkManager!
    private var mockViewManager: ViewManager!
    private var mockMetricsManager: MetricsManager!

    override func setUpWithError() throws {
        mockSpanData = makeNetworkRequestMockSpan()
        mockVersionMetadata = VersionMetadata(appName: "ExampleApp", appVersion: "1.1.1")
        mockSessionManager = SessionManager()
        mockNetworkManager = NetworkManager()
        mockViewManager = ViewManager(keyChain: KeychainManager())
        mockMetricsManager = MetricsManager()
    }

    override func tearDownWithError() throws {
        mockSpanData = nil
        mockVersionMetadata = nil
        mockSessionManager = nil
        mockNetworkManager = nil
        mockViewManager = nil
        mockMetricsManager = nil
    }

    private func makeNetworkRequestMockSpan() -> MockSpanData {
        // network-request event type → instrumentation_data is emitted.
        // Covers all attributes that the cx_rum.* mirror reads.
        return MockSpanData(
            attributes: [
                Keys.severity.rawValue: AttributeValue("3"),
                Keys.eventType.rawValue: AttributeValue(CoralogixEventType.networkRequest.rawValue),
                Keys.source.rawValue: AttributeValue("fetch"),
                Keys.environment.rawValue: AttributeValue("PROD"),
                Keys.userId.rawValue: AttributeValue("user-orig"),
                Keys.userName.rawValue: AttributeValue("Original Name"),
                Keys.userEmail.rawValue: AttributeValue("orig@example.com"),
                Keys.sessionId.rawValue: AttributeValue("session_001"),
                Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
                Keys.errorMessage.rawValue: AttributeValue("orig error"),
                Keys.errorType.rawValue: AttributeValue("OrigType"),
                SemanticAttributes.httpUrl.rawValue: AttributeValue("https://example.com/orig"),
                SemanticAttributes.httpMethod.rawValue: AttributeValue("GET"),
                SemanticAttributes.httpStatusCode.rawValue: AttributeValue("200"),
                SemanticAttributes.httpTarget.rawValue: AttributeValue("/orig"),
                SemanticAttributes.httpScheme.rawValue: AttributeValue("https"),
                SemanticAttributes.netPeerName.rawValue: AttributeValue("example.com")
            ],
            startTime: Date(),
            endTime: Date(),
            spanId: "20",
            traceId: "30",
            name: "testSpan",
            kind: 2,
            statusCode: ["status": "ok"],
            resources: [:]
        )
    }

    private func makeOptions(beforeSend: (([String: Any]) -> [String: Any]?)?) -> CoralogixExporterOptions {
        return CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "ExampleApp",
            version: "1.1.1",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: ["initial": "label"],
            beforeSend: beforeSend,
            debug: true
        )
    }

    /// Helper: spins a `CxSpan` through `beforeSend` and returns
    /// `(textCxRum, otelSpanAttributes)` — the two destinations a span lands in.
    private func runSpan(beforeSend: @escaping ([String: Any]) -> [String: Any]?) throws -> (text: [String: Any], otel: [String: Any]) {
        let options = makeOptions(beforeSend: beforeSend)
        guard let cxSpan = CxSpan(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            networkManager: mockNetworkManager,
            viewManager: mockViewManager,
            metricsManager: mockMetricsManager,
            options: options
        ) else {
            throw NSError(domain: "CxSpanInit", code: 0)
        }
        let dict = try XCTUnwrap(cxSpan.getDictionary())
        let textWrapper = try XCTUnwrap(dict[Keys.text.rawValue] as? [String: Any])
        let textCxRum = try XCTUnwrap(textWrapper[Keys.cxRum.rawValue] as? [String: Any])
        let inst = try XCTUnwrap(dict[Keys.instrumentationData.rawValue] as? [String: Any])
        let otelSpan = try XCTUnwrap(inst[Keys.otelSpan.rawValue] as? [String: Any])
        let attrs = try XCTUnwrap(otelSpan[Keys.attributes.rawValue] as? [String: Any])
        return (textCxRum, attrs)
    }

    // MARK: - Editable field propagation (text.cx_rum ↔ instrumentation_data parity)
    //
    // For each editable field, change the value via `beforeSend` and assert the
    // modification appears in BOTH text.cx_rum AND instrumentation_data.otelSpan.attributes.
    // This is the primary acceptance test for CX-44686.

    func test_severity_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var ec = edit[Keys.eventContext.rawValue] as? [String: Any] {
                ec[Keys.severity.rawValue] = 5
                edit[Keys.eventContext.rawValue] = ec
            }
            return edit
        }
        let textSeverity = (result.text[Keys.eventContext.rawValue] as? [String: Any])?[Keys.severity.rawValue] as? Int
        XCTAssertEqual(textSeverity, 5)
        XCTAssertEqual(result.otel["cx_rum.event_context.severity"] as? Int, 5)
    }

    func test_eventSource_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var ec = edit[Keys.eventContext.rawValue] as? [String: Any] {
                ec[Keys.source.rawValue] = "modified-source"
                edit[Keys.eventContext.rawValue] = ec
            }
            return edit
        }
        let textSource = (result.text[Keys.eventContext.rawValue] as? [String: Any])?[Keys.source.rawValue] as? String
        XCTAssertEqual(textSource, "modified-source")
        XCTAssertEqual(result.otel["cx_rum.event_context.source"] as? String, "modified-source")
    }

    func test_userEmail_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var sc = edit[Keys.sessionContext.rawValue] as? [String: Any] {
                sc[Keys.userEmail.rawValue] = "redacted@coralogix.com"
                edit[Keys.sessionContext.rawValue] = sc
            }
            return edit
        }
        let textEmail = (result.text[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.userEmail.rawValue] as? String
        XCTAssertEqual(textEmail, "redacted@coralogix.com")
        XCTAssertEqual(result.otel["cx_rum.session_context.user_email"] as? String, "redacted@coralogix.com")
    }

    func test_userName_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var sc = edit[Keys.sessionContext.rawValue] as? [String: Any] {
                sc[Keys.userName.rawValue] = "Modified Name"
                edit[Keys.sessionContext.rawValue] = sc
            }
            return edit
        }
        let textName = (result.text[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.userName.rawValue] as? String
        XCTAssertEqual(textName, "Modified Name")
        XCTAssertEqual(result.otel["cx_rum.session_context.user_name"] as? String, "Modified Name")
    }

    func test_userId_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var sc = edit[Keys.sessionContext.rawValue] as? [String: Any] {
                sc[Keys.userId.rawValue] = "user-edited-42"
                edit[Keys.sessionContext.rawValue] = sc
            }
            return edit
        }
        let textId = (result.text[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.userId.rawValue] as? String
        XCTAssertEqual(textId, "user-edited-42")
        XCTAssertEqual(result.otel["cx_rum.session_context.user_id"] as? String, "user-edited-42")
    }

    func test_errorType_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var ec = edit[Keys.errorContext.rawValue] as? [String: Any] {
                ec[Keys.errorType.rawValue] = "ModifiedType"
                edit[Keys.errorContext.rawValue] = ec
            } else {
                edit[Keys.errorContext.rawValue] = [Keys.errorType.rawValue: "ModifiedType"]
            }
            return edit
        }
        // errorContext only appears in text.cx_rum when event type is .error.
        // For network-request events, the cx_rum.* mirror still surfaces error_type
        // when present in the dict, so we only assert the mirror side here.
        XCTAssertEqual(result.otel["cx_rum.error_context.error_type"] as? String, "ModifiedType")
    }

    func test_errorMessage_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var ec = edit[Keys.errorContext.rawValue] as? [String: Any] {
                ec[Keys.errorMessage.rawValue] = "redacted error"
                edit[Keys.errorContext.rawValue] = ec
            } else {
                edit[Keys.errorContext.rawValue] = [Keys.errorMessage.rawValue: "redacted error"]
            }
            return edit
        }
        XCTAssertEqual(result.otel["cx_rum.error_context.error_message"] as? String, "redacted error")
    }

    func test_networkUrl_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var nrc = edit[Keys.networkRequestContext.rawValue] as? [String: Any] {
                nrc[Keys.url.rawValue] = "https://example.com/redacted"
                edit[Keys.networkRequestContext.rawValue] = nrc
            }
            return edit
        }
        let textUrl = (result.text[Keys.networkRequestContext.rawValue] as? [String: Any])?[Keys.url.rawValue] as? String
        XCTAssertEqual(textUrl, "https://example.com/redacted")
        XCTAssertEqual(result.otel["cx_rum.network_request_context.url"] as? String, "https://example.com/redacted")
    }

    func test_networkMethod_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var nrc = edit[Keys.networkRequestContext.rawValue] as? [String: Any] {
                nrc[Keys.method.rawValue] = "POST"
                edit[Keys.networkRequestContext.rawValue] = nrc
            }
            return edit
        }
        XCTAssertEqual(result.otel["cx_rum.network_request_context.method"] as? String, "POST")
    }

    func test_networkStatusCode_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var nrc = edit[Keys.networkRequestContext.rawValue] as? [String: Any] {
                nrc[Keys.statusCode.rawValue] = 503
                edit[Keys.networkRequestContext.rawValue] = nrc
            }
            return edit
        }
        XCTAssertEqual(result.otel["cx_rum.network_request_context.status_code"] as? Int, 503)
    }

    func test_networkFragments_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var nrc = edit[Keys.networkRequestContext.rawValue] as? [String: Any] {
                nrc[Keys.fragments.rawValue] = "/redacted-path"
                edit[Keys.networkRequestContext.rawValue] = nrc
            }
            return edit
        }
        XCTAssertEqual(result.otel["cx_rum.network_request_context.fragments"] as? String, "/redacted-path")
    }

    func test_networkRequestHeaders_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var nrc = edit[Keys.networkRequestContext.rawValue] as? [String: Any] {
                nrc[Keys.requestHeaders.rawValue] = ["X-Tenant": "redacted"]
                edit[Keys.networkRequestContext.rawValue] = nrc
            }
            return edit
        }
        let headers = result.otel["cx_rum.network_request_context.request_headers"] as? [String: Any]
        XCTAssertEqual(headers?["X-Tenant"] as? String, "redacted")
    }

    func test_networkRequestPayload_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var nrc = edit[Keys.networkRequestContext.rawValue] as? [String: Any] {
                nrc[Keys.requestPayload.rawValue] = "<redacted-body>"
                edit[Keys.networkRequestContext.rawValue] = nrc
            }
            return edit
        }
        XCTAssertEqual(result.otel["cx_rum.network_request_context.request_payload"] as? String, "<redacted-body>")
    }

    func test_environment_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            edit[Keys.environment.rawValue] = "staging-rewritten"
            return edit
        }
        XCTAssertEqual(result.text[Keys.environment.rawValue] as? String, "staging-rewritten")
        XCTAssertEqual(result.otel["cx_rum.environment"] as? String, "staging-rewritten")
    }

    func test_labels_propagateToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            edit[Keys.labels.rawValue] = ["team": "mobile", "tier": "edited"]
            return edit
        }
        let textLabels = result.text[Keys.labels.rawValue] as? [String: Any]
        XCTAssertEqual(textLabels?["tier"] as? String, "edited")
        let otelLabels = result.otel["cx_rum.labels"] as? [String: Any]
        XCTAssertEqual(otelLabels?["team"] as? String, "mobile")
        XCTAssertEqual(otelLabels?["tier"] as? String, "edited")
    }

    func test_versionMetadataAppName_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var vm = edit[Keys.versionMetaData.rawValue] as? [String: Any] {
                vm[Keys.appName.rawValue] = "EditedApp"
                edit[Keys.versionMetaData.rawValue] = vm
            }
            return edit
        }
        XCTAssertEqual(result.otel["cx_rum.version_metadata.app_name"] as? String, "EditedApp")
    }

    func test_versionMetadataAppVersion_propagatesToInstrumentationData() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            if var vm = edit[Keys.versionMetaData.rawValue] as? [String: Any] {
                vm[Keys.appVersion.rawValue] = "9.9.9"
                edit[Keys.versionMetaData.rawValue] = vm
            }
            return edit
        }
        XCTAssertEqual(result.otel["cx_rum.version_metadata.app_version"] as? String, "9.9.9")
    }

    // MARK: - Read-only field stripping
    //
    // The editable subset passed to `beforeSend` must not include identity,
    // dedup, counter, or runtime-constant fields. A customer attempting to
    // inject any of these in their return dict must NOT see the value flow
    // through to the final payload.

    func test_subset_doesNotContainReadOnlyFields() throws {
        // Capture the subset by spying through a no-op beforeSend.
        var captured: [String: Any] = [:]
        _ = try runSpan { cxRum in
            captured = cxRum
            return cxRum
        }
        // All keys listed in CxSpan.readOnlyCxRumKeys must be absent from the subset.
        XCTAssertNil(captured[Keys.isSnapshotEvent.rawValue], "isSnapshotEvent must not be editable")
        XCTAssertNil(captured[Keys.traceId.rawValue], "traceId must not be editable")
        XCTAssertNil(captured[Keys.spanId.rawValue], "spanId must not be editable")
        XCTAssertNil(captured[Keys.fingerPrint.rawValue], "fingerPrint must not be editable")
        XCTAssertNil(captured[Keys.prevSession.rawValue], "prevSession must not be editable")
        XCTAssertNil(captured[Keys.platform.rawValue], "platform must not be editable")
        XCTAssertNil(captured[Keys.snapshotContext.rawValue], "snapshotContext must not be editable")
        XCTAssertNil(captured[Keys.mobileSdk.rawValue], "mobileSdk must not be editable")
        XCTAssertNil(captured[Keys.timestamp.rawValue], "timestamp must not be editable")

        if let session = captured[Keys.sessionContext.rawValue] as? [String: Any] {
            XCTAssertNil(session[Keys.sessionId.rawValue], "sessionContext.sessionId must not be editable")
            XCTAssertNil(session[Keys.sessionCreationDate.rawValue], "sessionContext.sessionCreationDate must not be editable")
        }
    }

    func test_isSnapshotEvent_injectionIsIgnored() throws {
        // First capture whether the SDK emitted a snapshot for this fixture (depends on
        // SessionManager state — a fresh session always emits one). The test then asserts
        // the SDK's value wins regardless of what the customer injects.
        var sdkValue: Bool?
        _ = try runSpan { cxRum in
            sdkValue = cxRum[Keys.isSnapshotEvent.rawValue] as? Bool   // captured before injection
            return cxRum
        }

        let result = try runSpan { cxRum in
            var edit = cxRum
            // Inject the OPPOSITE of whatever the SDK produced, so any leak is detectable.
            edit[Keys.isSnapshotEvent.rawValue] = !(sdkValue ?? false)
            return edit
        }
        XCTAssertEqual(result.text[Keys.isSnapshotEvent.rawValue] as? Bool, sdkValue,
                       "isSnapshotEvent must be restored from the original cx_rum, not the callback's injected value")
    }

    func test_traceId_injectionIsIgnored() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            edit[Keys.traceId.rawValue] = "FORGED-TRACE-ID"
            return edit
        }
        XCTAssertEqual(result.text[Keys.traceId.rawValue] as? String, "30",
                       "traceId must be restored from the original cx_rum after beforeSend")
    }

    func test_spanId_injectionIsIgnored() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            edit[Keys.spanId.rawValue] = "FORGED-SPAN-ID"
            return edit
        }
        XCTAssertEqual(result.text[Keys.spanId.rawValue] as? String, "20",
                       "spanId must be restored from the original cx_rum after beforeSend")
    }

    func test_fingerPrint_injectionIsIgnored() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            edit[Keys.fingerPrint.rawValue] = "FORGED-FINGERPRINT"
            return edit
        }
        let fp = result.text[Keys.fingerPrint.rawValue] as? String
        XCTAssertNotEqual(fp, "FORGED-FINGERPRINT", "fingerPrint must not be forgeable")
    }

    func test_sessionId_injectionIsIgnored() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            var session = (edit[Keys.sessionContext.rawValue] as? [String: Any]) ?? [:]
            session[Keys.sessionId.rawValue] = "FORGED-SESSION"
            edit[Keys.sessionContext.rawValue] = session
            return edit
        }
        let sessionId = (result.text[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.sessionId.rawValue] as? String
        XCTAssertNotEqual(sessionId, "FORGED-SESSION", "sessionId must be restored from the original cx_rum")
    }

    func test_platform_injectionIsIgnored() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            edit[Keys.platform.rawValue] = "console"
            return edit
        }
        let platform = result.text[Keys.platform.rawValue] as? String
        XCTAssertNotEqual(platform, "console", "platform must be restored from the original cx_rum")
    }

    func test_mobileSdk_injectionIsIgnored() throws {
        let result = try runSpan { cxRum in
            var edit = cxRum
            edit[Keys.mobileSdk.rawValue] = ["sdk_version": "9.9.9-forged"]
            return edit
        }
        let injected = (result.text[Keys.mobileSdk.rawValue] as? [String: Any])?["sdk_version"] as? String
        XCTAssertNotEqual(injected, "9.9.9-forged", "mobileSdk must be restored from the original cx_rum")
    }

    // MARK: - Baseline parity: no beforeSend → mirror still matches the cx_rum dict.

    func test_noBeforeSend_attributesStillMatchCxRum() throws {
        let options = makeOptions(beforeSend: nil)
        guard let cxSpan = CxSpan(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            networkManager: mockNetworkManager,
            viewManager: mockViewManager,
            metricsManager: mockMetricsManager,
            options: options
        ) else { return XCTFail("CxSpan init failed") }

        let dict = try XCTUnwrap(cxSpan.getDictionary())
        let text = try XCTUnwrap(dict[Keys.text.rawValue] as? [String: Any])
        let cxRum = try XCTUnwrap(text[Keys.cxRum.rawValue] as? [String: Any])
        let inst = try XCTUnwrap(dict[Keys.instrumentationData.rawValue] as? [String: Any])
        let otel = try XCTUnwrap(inst[Keys.otelSpan.rawValue] as? [String: Any])
        let attrs = try XCTUnwrap(otel[Keys.attributes.rawValue] as? [String: Any])

        let textSeverity = (cxRum[Keys.eventContext.rawValue] as? [String: Any])?[Keys.severity.rawValue] as? Int
        XCTAssertEqual(attrs["cx_rum.event_context.severity"] as? Int, textSeverity)

        let textEmail = (cxRum[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.userEmail.rawValue] as? String
        XCTAssertEqual(attrs["cx_rum.session_context.user_email"] as? String, textEmail)

        let textUrl = (cxRum[Keys.networkRequestContext.rawValue] as? [String: Any])?[Keys.url.rawValue] as? String
        XCTAssertEqual(attrs["cx_rum.network_request_context.url"] as? String, textUrl)
    }
}
