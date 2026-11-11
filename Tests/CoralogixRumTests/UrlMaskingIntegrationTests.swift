//
//  UrlMaskingIntegrationTests.swift
//  Coralogix
//
//  Where masking sits in the pipeline: `ignoreUrls` sees the original URL; the uploaded event,
//  `beforeSend`, `tracesExporter` and hybrid-reported requests only ever see the masked one.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class UrlMaskingIntegrationTests: XCTestCase {

    private static let secretUrl = "https://api.example.com/callback?code=abc&foo=1#access_token=xyz"
    private static let maskedUrl = "https://api.example.com/callback?code=[REDACTED]&foo=1#access_token=[REDACTED]"

    private var rum: CoralogixRum?

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        CoralogixRum.isInitialized = false
        CoralogixRum.mobileSDK = MobileSDK()
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func startSDK(ignoreUrls: [String] = [],
                          beforeSend: (([String: Any]) -> [String: Any]?)? = nil,
                          tracesExporter: TracesExporterCallback? = nil,
                          urlMasking: UrlMaskingOptions = UrlMaskingOptions()) throws -> (CoralogixExporter, CapturingUploader) {
        let rum = CoralogixRum(options: CoralogixExporterOptions(
            coralogixDomain: .US2,
            environment: "PROD",
            application: "UrlMaskingTest",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: ignoreUrls,
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            beforeSend: beforeSend,
            tracesExporter: tracesExporter,
            urlMasking: urlMasking,
            debug: true
        ))
        self.rum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = CapturingUploader()
        exporter.spanUploader = uploader
        return (exporter, uploader)
    }

    private func makeNetworkSpan(url: String) -> SpanData {
        let attributes: [String: AttributeValue] = [
            Keys.severity.rawValue: AttributeValue("3"),
            Keys.eventType.rawValue: AttributeValue(CoralogixEventType.networkRequest.rawValue),
            Keys.source.rawValue: AttributeValue("fetch"),
            Keys.environment.rawValue: AttributeValue("prod"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
            SemanticAttributes.httpUrl.rawValue: AttributeValue(url),
            SemanticAttributes.httpMethod.rawValue: AttributeValue("GET"),
            SemanticAttributes.httpStatusCode.rawValue: AttributeValue(200),
            SemanticAttributes.httpTarget.rawValue: AttributeValue("/callback"),
            SemanticAttributes.netPeerName.rawValue: AttributeValue("api.example.com")
        ]
        return SpanData(traceId: TraceId.random(),
                        spanId: SpanId.random(),
                        name: "HTTP GET",
                        kind: .client,
                        startTime: Date(),
                        attributes: attributes,
                        endTime: Date(),
                        hasEnded: true)
    }

    private func uploadedNetworkUrl(_ uploader: CapturingUploader) -> String? {
        for event in uploader.uploadedSpans {
            let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
            if let url = (cxRum?[Keys.networkRequestContext.rawValue] as? [String: Any])?[Keys.url.rawValue] as? String {
                return url
            }
        }
        return nil
    }

    // MARK: - Native export path

    func test_export_uploadsMaskedNetworkUrl() throws {
        let (exporter, uploader) = try startSDK()
        _ = exporter.export(spans: [makeNetworkSpan(url: Self.secretUrl)], explicitTimeout: nil)
        XCTAssertEqual(uploadedNetworkUrl(uploader), Self.maskedUrl)
    }

    func test_export_dropQueryMode_uploadsUrlWithoutQueryOrFragment() throws {
        let (exporter, uploader) = try startSDK(urlMasking: UrlMaskingOptions(mode: .dropQuery))
        _ = exporter.export(spans: [makeNetworkSpan(url: Self.secretUrl)], explicitTimeout: nil)
        XCTAssertEqual(uploadedNetworkUrl(uploader), "https://api.example.com/callback")
    }

    func test_export_additionalParams_masksCustomerParam() throws {
        let (exporter, uploader) = try startSDK(urlMasking: UrlMaskingOptions(additionalParams: ["foo"]))
        _ = exporter.export(spans: [makeNetworkSpan(url: Self.secretUrl)], explicitTimeout: nil)
        XCTAssertEqual(uploadedNetworkUrl(uploader),
                       "https://api.example.com/callback?code=[REDACTED]&foo=[REDACTED]#access_token=[REDACTED]")
    }

    func test_export_instrumentationDataCarriesMaskedUrl() throws {
        let (exporter, uploader) = try startSDK()
        _ = exporter.export(spans: [makeNetworkSpan(url: Self.secretUrl)], explicitTimeout: nil)
        let event = try XCTUnwrap(uploader.uploadedSpans.first)
        let json = String(data: try JSONSerialization.data(withJSONObject: event[Keys.instrumentationData.rawValue] ?? [:]), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("code=[REDACTED]"), "instrumentation_data must carry the masked URL: \(json)")
        XCTAssertFalse(json.contains("code=abc"), "instrumentation_data must not also carry the raw URL: \(json)")
    }

    func test_beforeSend_seesMaskedUrl() throws {
        var seenUrl: String?
        let (exporter, _) = try startSDK(beforeSend: { cxRum in
            seenUrl = (cxRum[Keys.networkRequestContext.rawValue] as? [String: Any])?[Keys.url.rawValue] as? String
            return cxRum
        })
        _ = exporter.export(spans: [makeNetworkSpan(url: Self.secretUrl)], explicitTimeout: nil)
        XCTAssertEqual(seenUrl, Self.maskedUrl)
    }

    func test_tracesExporter_receivesMaskedUrl() throws {
        var json = ""
        let (exporter, _) = try startSDK(tracesExporter: { data in
            json = data.jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        })
        _ = exporter.export(spans: [makeNetworkSpan(url: Self.secretUrl)], explicitTimeout: nil)
        XCTAssertTrue(json.contains("code=[REDACTED]"), "tracesExporter must receive the masked URL: \(json)")
        XCTAssertFalse(json.contains("code=abc"), "tracesExporter must not also receive the raw URL: \(json)")
    }

    /// `ignoreUrls` matches the URL as the app sent it: a rule written against a secret-bearing
    /// query keeps working after masking ships.
    func test_ignoreUrls_matchesOriginalUrl() throws {
        let (exporter, uploader) = try startSDK(ignoreUrls: ["code=abc"])
        let result = exporter.export(spans: [makeNetworkSpan(url: Self.secretUrl)], explicitTimeout: nil)
        XCTAssertEqual(result, .failure, "A span whose original URL matches ignoreUrls is filtered out")
        XCTAssertNil(uploadedNetworkUrl(uploader))
    }

    // MARK: - Error fields

    /// A URLSession failure reported through `reportError` carries the failing URL in its
    /// userInfo, and hybrid stack frames carry script URLs in `fileName`.
    func test_export_masksErrorUserInfoAndStackFrameUrls() throws {
        let (exporter, uploader) = try startSDK()
        let userInfo = #"{"NSErrorFailingURLStringKey":"\#(Self.secretUrl)"}"#
        let stackTrace = #"[{"fileName":"https://cdn.x.com/bundle.js?token=abc","lineNumber":1}]"#
        let span = SpanData(traceId: TraceId.random(),
                            spanId: SpanId.random(),
                            name: "error",
                            kind: .client,
                            startTime: Date(),
                            attributes: [
                                Keys.severity.rawValue: AttributeValue("5"),
                                Keys.eventType.rawValue: AttributeValue(CoralogixEventType.error.rawValue),
                                Keys.source.rawValue: AttributeValue("console"),
                                Keys.sessionId.rawValue: AttributeValue("session_001"),
                                Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
                                Keys.errorMessage.rawValue: AttributeValue("The request timed out."),
                                Keys.userInfo.rawValue: AttributeValue(userInfo),
                                Keys.stackTrace.rawValue: AttributeValue(stackTrace)
                            ],
                            endTime: Date(),
                            hasEnded: true)
        _ = exporter.export(spans: [span], explicitTimeout: nil)

        let cxRum = try XCTUnwrap((uploader.uploadedSpans.first?[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any])
        let errorContext = try XCTUnwrap(cxRum[Keys.errorContext.rawValue] as? [String: Any])
        let reportedUserInfo = try XCTUnwrap(errorContext[Keys.userInfo.rawValue] as? [String: Any])
        XCTAssertEqual(reportedUserInfo["NSErrorFailingURLStringKey"] as? String, Self.maskedUrl)
        let frames = try XCTUnwrap(errorContext[Keys.originalStackTrace.rawValue] as? [[String: Any]])
        XCTAssertEqual(frames.first?["fileName"] as? String, "https://cdn.x.com/bundle.js?token=[REDACTED]")
    }

    // MARK: - Hybrid bridge

    func test_hybridReportedRequest_isMasked() throws {
        let (_, uploader) = try startSDK()
        let rum = try XCTUnwrap(self.rum)
        rum.setNetworkRequestContext(dictionary: [
            Keys.url.rawValue: Self.secretUrl,
            Keys.host.rawValue: "api.example.com",
            Keys.method.rawValue: "GET",
            Keys.statusCode.rawValue: 200,
            Keys.duration.rawValue: 10,
            Keys.httpResponseBodySize.rawValue: 0,
            Keys.fragments.rawValue: "/callback?code=abc",
            Keys.schema.rawValue: "https"
        ])

        let deadline = Date().addingTimeInterval(5)
        var url: String?
        while url == nil, Date() < deadline {
            (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
            url = uploadedNetworkUrl(uploader)
            if url == nil { Thread.sleep(forTimeInterval: 0.1) }
        }
        XCTAssertEqual(url, Self.maskedUrl)
        let fragments = uploader.uploadedSpans.compactMap {
            (($0[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any])?[Keys.networkRequestContext.rawValue] as? [String: Any]
        }.first?[Keys.fragments.rawValue] as? String
        XCTAssertEqual(fragments, "/callback?code=[REDACTED]")
    }

    func test_hybridBeforeSendCallBack_receivesMaskedUrl() throws {
        var opts = CoralogixExporterOptions(coralogixDomain: .US2,
                                            environment: "PROD",
                                            application: "UrlMaskingTest",
                                            version: "1.0",
                                            publicKey: "token",
                                            ignoreUrls: [],
                                            ignoreErrors: [],
                                            labels: [:],
                                            debug: true)
        let lock = NSLock()
        var received: [[String: Any]] = []
        opts.beforeSendCallBack = { events in
            lock.lock(); defer { lock.unlock() }
            received.append(contentsOf: events)
        }
        let rum = CoralogixRum(options: opts, sdkFramework: .flutter(version: "1.0.0"))
        self.rum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        _ = exporter.export(spans: [makeNetworkSpan(url: Self.secretUrl)], explicitTimeout: nil)

        lock.lock(); defer { lock.unlock() }
        let urls = received.compactMap {
            ((($0[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any])?[Keys.networkRequestContext.rawValue] as? [String: Any])?[Keys.url.rawValue] as? String
        }
        XCTAssertEqual(urls, [Self.maskedUrl])
    }

    // MARK: - Failed requests

    /// Polls the uploader until an exported network event's URL contains `marker`, then returns the
    /// whole uploaded event serialized, so a secret anywhere in it (not just in `url`) is visible.
    private func uploadedEventJson(urlContaining marker: String, _ uploader: CapturingUploader) -> String? {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
            for event in uploader.uploadedSpans {
                let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
                let url = (cxRum?[Keys.networkRequestContext.rawValue] as? [String: Any])?[Keys.url.rawValue] as? String
                if url?.contains(marker) == true,
                   let data = try? JSONSerialization.data(withJSONObject: event, options: [.withoutEscapingSlashes]) {
                    return String(data: data, encoding: .utf8)
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    /// A Flutter `ClientException` repeats the request URL in its message, and older hybrid plugins
    /// send it as `error_message`. iOS does not export `error_message` on network events, so the raw
    /// value must not appear anywhere in the uploaded event while the URL itself arrives masked.
    func test_failedHybridRequest_errorMessageWithUrl_doesNotLeakSecret() throws {
        let (_, uploader) = try startSDK()
        let rum = try XCTUnwrap(self.rum)
        rum.setNetworkRequestContext(dictionary: [
            Keys.url.rawValue: "https://api.example.com/hybrid-fail?code=leak1&page=2",
            Keys.host.rawValue: "api.example.com",
            Keys.method.rawValue: "GET",
            Keys.statusCode.rawValue: 0,
            Keys.statusText.rawValue: "",
            Keys.duration.rawValue: 10,
            Keys.httpResponseBodySize.rawValue: 0,
            Keys.fragments.rawValue: "/hybrid-fail",
            Keys.schema.rawValue: "https",
            Keys.errorMessage.rawValue: "ClientException: Connection closed, uri=https://api.example.com/hybrid-fail?code=leak1&page=2"
        ])
        let json = try XCTUnwrap(uploadedEventJson(urlContaining: "hybrid-fail", uploader))
        XCTAssertTrue(json.contains("hybrid-fail?code=[REDACTED]&page=2"), json)
        XCTAssertFalse(json.contains("leak1"), "The raw secret must not reach the uploaded event: \(json)")
    }

    /// A URLSession request that fails at the transport layer (connection refused): the SDK records
    /// no error description on the network span, so the failing URL's secret cannot ride along.
    func test_failedUrlSessionRequest_doesNotLeakSecret() throws {
        let (_, uploader) = try startSDK()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:1/native-fail?code=leak2&page=2"))
        let done = expectation(description: "request failed")
        URLSession.shared.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error, "The request is expected to fail")
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
        let json = try XCTUnwrap(uploadedEventJson(urlContaining: "native-fail", uploader))
        XCTAssertTrue(json.contains("native-fail?code=[REDACTED]&page=2"), json)
        XCTAssertFalse(json.contains("leak2"), "The raw secret must not reach the uploaded event: \(json)")
    }

    // MARK: - Views

    func test_setView_masksUrlLikeViewName() throws {
        let (exporter, _) = try startSDK()
        let rum = try XCTUnwrap(self.rum)
        rum.setView(name: "/reset?token=abc")
        XCTAssertEqual(exporter.getViewManager().currentViewName, "/reset?token=[REDACTED]")
    }

    /// Two routes that mask to the same name are still two views: the change is decided on the
    /// raw name. Setting the same raw route again is not a new view.
    func test_viewChange_isDecidedOnTheRawName() throws {
        let (exporter, _) = try startSDK(urlMasking: UrlMaskingOptions(mode: .dropQuery))
        let rum = try XCTUnwrap(self.rum)
        let viewManager = exporter.getViewManager()
        rum.setView(name: "/reset?token=a")
        rum.setView(name: "/reset?token=b")
        XCTAssertEqual(viewManager.currentViewName, "/reset")
        XCTAssertEqual(viewManager.getUniqueViewCount(), 2)
        XCTAssertEqual(viewManager.getViewNumber(), 1)
        rum.setView(name: "/reset?token=b")
        XCTAssertEqual(viewManager.getViewNumber(), 1)
    }

    /// An error or crash message often repeats the URL that failed: only the URL in it is masked.
    func test_errorMessage_masksOnlyTheUrlInside() throws {
        let (exporter, uploader) = try startSDK()
        let span = SpanData(traceId: TraceId.random(),
                            spanId: SpanId.random(),
                            name: "error",
                            kind: .client,
                            startTime: Date(),
                            attributes: [
                                Keys.severity.rawValue: AttributeValue("5"),
                                Keys.eventType.rawValue: AttributeValue(CoralogixEventType.error.rawValue),
                                Keys.source.rawValue: AttributeValue("console"),
                                Keys.sessionId.rawValue: AttributeValue("session_001"),
                                Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
                                Keys.errorMessage.rawValue: AttributeValue("ClientException: Connection closed, uri=https://api.example.com/cb?code=abc&page=2 (retry? code=7)")
                            ],
                            endTime: Date(),
                            hasEnded: true)
        _ = exporter.export(spans: [span], explicitTimeout: nil)
        let cxRum = try XCTUnwrap((uploader.uploadedSpans.first?[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any])
        let errorContext = try XCTUnwrap(cxRum[Keys.errorContext.rawValue] as? [String: Any])
        XCTAssertEqual(errorContext[Keys.errorMessage.rawValue] as? String,
                       "ClientException: Connection closed, uri=https://api.example.com/cb?code=[REDACTED]&page=2 (retry? code=7)")
    }

    /// `reportError(message:)` reports as an error-severity log: the URL in its message is masked,
    /// while an info log's message is left as the app wrote it.
    func test_reportErrorMessage_masksOnlyTheUrlInside() throws {
        let (exporter, uploader) = try startSDK()
        func logSpan(severity: CoralogixLogSeverity, message: String) -> SpanData {
            SpanData(traceId: TraceId.random(), spanId: SpanId.random(), name: "log", kind: .client, startTime: Date(),
                     attributes: [
                        Keys.severity.rawValue: AttributeValue(severity.rawValue),
                        Keys.eventType.rawValue: AttributeValue(CoralogixEventType.log.rawValue),
                        Keys.source.rawValue: AttributeValue("code"),
                        Keys.sessionId.rawValue: AttributeValue("session_001"),
                        Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
                        Keys.message.rawValue: AttributeValue(message)
                     ],
                     endTime: Date(), hasEnded: true)
        }
        _ = exporter.export(spans: [
            logSpan(severity: .error, message: "failed: uri=https://x.com/cb?code=abc&page=2 (code=7)"),
            logSpan(severity: .info, message: "opened https://x.com/cb?code=abc")
        ], explicitTimeout: nil)
        let messages = uploader.uploadedSpans.compactMap {
            (((($0[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any])?[Keys.logContext.rawValue] as? [String: Any])?[Keys.message.rawValue] as? String)
        }
        XCTAssertEqual(Set(messages), ["failed: uri=https://x.com/cb?code=[REDACTED]&page=2 (code=7)", "opened https://x.com/cb?code=abc"])
    }

    // MARK: - Headers stay allow-list only

    func test_headers_authorizationCapturedOnlyWhenListed() {
        let headers = ["Authorization": "Bearer x", "Accept": "application/json"]
        XCTAssertEqual(NetworkCaptureRule.filterHeaders(headers, allowlist: ["Accept"]),
                       ["Accept": "application/json"])
        XCTAssertEqual(NetworkCaptureRule.filterHeaders(headers, allowlist: ["Authorization"]),
                       ["Authorization": "Bearer x"])
    }
}

private final class CapturingUploader: SpanUploading {
    private let lock = NSLock()
    private var _uploadedSpans: [[String: Any]] = []

    var uploadedSpans: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return _uploadedSpans
    }

    func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
        lock.lock(); defer { lock.unlock() }
        _uploadedSpans.append(contentsOf: spans)
        return .success
    }
}
