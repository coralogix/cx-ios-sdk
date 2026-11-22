//
//  EventSourceTests.swift
//
//  `cx_rum.event_context.source` is set only on errors, logs and network requests — as the
//  browser SDK does — and on an error it records how the error was caught.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class EventSourceHybridResolutionTests: XCTestCase {

    func test_theFourValuesAWrapperMaySend_areKept() {
        XCTAssertEqual(EventSource.hybrid("captured"), .captured)
        XCTAssertEqual(EventSource.hybrid("crash"), .crash)
        XCTAssertEqual(EventSource.hybrid("console"), .console)
        XCTAssertEqual(EventSource.hybrid("code"), .code)
    }

    /// A wrapper that predates the field sends nothing; it only reaches native through its
    /// customer-facing `reportError`, so the fallback is `captured`, whatever `isCrash` says.
    func test_noValue_fallsBackToCaptured() {
        XCTAssertEqual(EventSource.hybrid(nil), .captured)
    }

    /// `window` and `unhandledrejection` are what the RUM UI counts as crashes; `anr` and
    /// `fetch` are produced natively only; the match is exact.
    func test_anUnsupportedValue_fallsBackToCaptured() {
        for raw in ["window", "unhandledrejection", "anr", "fetch", "Captured", "CRASH", "", " code"] {
            XCTAssertEqual(EventSource.hybrid(raw), .captured, "'\(raw)'")
        }
    }

    func test_wireValues_matchTheAndroidSdk() {
        XCTAssertEqual(EventSource.captured.rawValue, "captured")
        XCTAssertEqual(EventSource.crash.rawValue, "crash")
        XCTAssertEqual(EventSource.anr.rawValue, "anr")
        XCTAssertEqual(EventSource.console.rawValue, "console")
        XCTAssertEqual(EventSource.code.rawValue, "code")
        XCTAssertEqual(EventSource.fetch.rawValue, "fetch")
    }
}

final class EventSourceWireTests: XCTestCase {

    private var rum: CoralogixRum?

    override func tearDownWithError() throws {
        rum?.shutdown()
        rum = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// One uploaded event: its `cx_rum` and, for the event types that carry one (network
    /// requests and custom spans), the OTLP mirror of it.
    private struct Uploaded {
        let cxRum: [String: Any]
        let otelAttributes: [String: Any]?

        var eventContext: [String: Any] { cxRum[Keys.eventContext.rawValue] as? [String: Any] ?? [:] }
        var type: String? { eventContext[Keys.type.rawValue] as? String }
        var source: String? { eventContext[Keys.source.rawValue] as? String }
        var hasSourceKey: Bool { eventContext.keys.contains(Keys.source.rawValue) }
        var otelSource: Any? { otelAttributes?["cx_rum.event_context.source"] }
        var errorContext: [String: Any] { cxRum[Keys.errorContext.rawValue] as? [String: Any] ?? [:] }
        var logMessage: String? { (cxRum[Keys.logContext.rawValue] as? [String: Any])?[Keys.message.rawValue] as? String }
    }

    private func start(framework: SdkFramework = .swift) throws -> (CoralogixRum, CapturingSpanUploader) {
        let sdk = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []), sdkFramework: framework)
        rum = sdk
        let uploader = CapturingSpanUploader()
        try XCTUnwrap(sdk.coralogixExporter).spanUploader = uploader
        return (sdk, uploader)
    }

    private func uploaded(_ uploader: CapturingSpanUploader) -> [Uploaded] {
        uploader.uploadedSpans.compactMap { event in
            guard let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any] else {
                return nil
            }
            let otel = ((event[Keys.instrumentationData.rawValue] as? [String: Any])?[Keys.otelSpan.rawValue]
                        as? [String: Any])?[Keys.attributes.rawValue] as? [String: Any]
            return Uploaded(cxRum: cxRum, otelAttributes: otel)
        }
    }

    /// Flushes until an event matching `match` is uploaded, and returns it.
    private func awaitEvent(_ sdk: CoralogixRum,
                            _ uploader: CapturingSpanUploader,
                            _ description: String,
                            where match: @escaping (Uploaded) -> Bool) throws -> Uploaded {
        var hit: Uploaded?
        let found = expectation(for: NSPredicate { [unowned self] _, _ in
            sdk.flush()
            hit = self.uploaded(uploader).first(where: match)
            return hit != nil
        }, evaluatedWith: nil)
        wait(for: [found], timeout: 10)
        return try XCTUnwrap(hit, description)
    }

    private func awaitError(_ sdk: CoralogixRum, _ uploader: CapturingSpanUploader, message: String) throws -> Uploaded {
        try awaitEvent(sdk, uploader, "error '\(message)'") {
            $0.type == CoralogixEventType.error.rawValue
                && $0.errorContext[Keys.errorMessage.rawValue] as? String == message
        }
    }

    private func assertSource(_ event: Uploaded, _ expected: EventSource,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(event.source, expected.rawValue, "cx_rum", file: file, line: line)
        if event.otelAttributes != nil {
            XCTAssertEqual(event.otelSource as? String, expected.rawValue, "OTLP mirror", file: file, line: line)
        }
    }

    /// The key is absent — not an empty string, not null — in both payload shapes.
    private func assertNoSource(_ event: Uploaded, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(event.hasSourceKey, "cx_rum.event_context of \(event.type ?? "?")", file: file, line: line)
        XCTAssertNil(event.otelSource, "OTLP mirror of \(event.type ?? "?")", file: file, line: line)
    }

    // MARK: - Native errors

    func test_nativeReportError_isCaptured_onEveryOverload() throws {
        let (sdk, uploader) = try start()
        sdk.reportError(error: NSError(domain: "Checkout", code: 7, userInfo: [NSLocalizedDescriptionKey: "ns error"]))
        sdk.reportError(exception: NSException(name: .invalidArgumentException, reason: "ns exception"))
        struct Failure: LocalizedError { var errorDescription: String? { "swift error" } }
        sdk.reportError(error: Failure())

        for message in ["ns error", "ns exception", "swift error"] {
            let event = try awaitError(sdk, uploader, message: message)
            assertSource(event, .captured)
            XCTAssertEqual(event.errorContext[Keys.isCrash.rawValue] as? Bool, false)
        }
    }

    /// A message has no error API on the browser either: it is a log, sourced `code`.
    func test_reportErrorWithAMessage_isALog_sourcedCode() throws {
        let (sdk, uploader) = try start()
        sdk.reportError(message: "message only")
        sdk.log(severity: .info, message: "plain log")

        for message in ["message only", "plain log"] {
            let event = try awaitEvent(sdk, uploader, "log '\(message)'") { $0.logMessage == message }
            XCTAssertEqual(event.type, CoralogixEventType.log.rawValue)
            assertSource(event, .code)
        }
    }

    // MARK: - Hybrid errors

    func test_hybridReportError_carriesTheSourceTheWrapperSent() throws {
        let (sdk, uploader) = try start(framework: .reactNative(version: "1.0.0"))
        let sent: [EventSource] = [.captured, .console, .code, .crash]
        for source in sent {
            sdk.reportError(message: "rn \(source.rawValue)", stackTrace: [], errorType: "Error",
                            isCrash: source == .crash, source: source.rawValue)
        }
        for source in sent {
            assertSource(try awaitError(sdk, uploader, message: "rn \(source.rawValue)"), source)
        }
    }

    /// `is_crash` is kept as the wrapper set it — the RUM UI's crash rate reads it, not the source.
    func test_hybridReportError_withoutASource_isCaptured_evenWhenItIsACrash() throws {
        let (sdk, uploader) = try start(framework: .reactNative(version: "1.0.0"))
        sdk.reportError(message: "old plugin fatal", stackTrace: [], errorType: "Error", isCrash: true)
        sdk.reportError(message: "unsupported", stackTrace: [], errorType: "Error", source: "window")

        let fatal = try awaitError(sdk, uploader, message: "old plugin fatal")
        assertSource(fatal, .captured)
        XCTAssertEqual(fatal.errorContext[Keys.isCrash.rawValue] as? Bool, true)
        assertSource(try awaitError(sdk, uploader, message: "unsupported"), .captured)
    }

    func test_obfuscatedFlutterError_carriesItsSourceAndIsCrash() throws {
        let (sdk, uploader) = try start(framework: .flutter(version: "1.0.0"))
        sdk.reportError(message: "dart auto", obfuscatedStackTrace: ["0x1"], source: "code")
        sdk.reportError(message: "dart fatal", obfuscatedStackTrace: ["0x1"], isCrash: true, source: "captured")

        let auto = try awaitError(sdk, uploader, message: "dart auto")
        assertSource(auto, .code)
        XCTAssertEqual(auto.errorContext[Keys.isCrash.rawValue] as? Bool, false)
        let fatal = try awaitError(sdk, uploader, message: "dart fatal")
        assertSource(fatal, .captured)
        XCTAssertEqual(fatal.errorContext[Keys.isCrash.rawValue] as? Bool, true)
    }

    // MARK: - Events that carry no source

    func test_customMeasurement_hasNoSource() throws {
        let (sdk, uploader) = try start()
        sdk.sendCustomMeasurement(name: "checkout", value: 1)
        let event = try awaitEvent(sdk, uploader, "custom-measurement") {
            $0.type == CoralogixEventType.customMeasurement.rawValue
        }
        assertNoSource(event)
    }

    /// Repo rule: an interaction change must hold on the hybrid path too, where the span comes
    /// from the bridge payload rather than the native swizzles.
    func test_hybridUserInteraction_hasNoSource() throws {
        let (sdk, uploader) = try start(framework: .flutter(version: "1.0.0"))
        sdk.setUserInteraction([Keys.eventName.rawValue: "click", Keys.targetElement.rawValue: "FlutterButton"])
        let event = try awaitEvent(sdk, uploader, "user-interaction") {
            $0.type == CoralogixEventType.userInteraction.rawValue
        }
        assertNoSource(event)
    }

    func test_hybridNavigation_hasNoSource() throws {
        let (sdk, uploader) = try start(framework: .flutter(version: "1.0.0"))
        sdk.setView(name: "Checkout")
        let event = try awaitEvent(sdk, uploader, "navigation") { $0.type == CoralogixEventType.navigation.rawValue }
        assertNoSource(event)
    }

    func test_theInitEvent_hasNoSource() throws {
        let (sdk, uploader) = try start()
        let event = try awaitEvent(sdk, uploader, "internal") { $0.type == CoralogixEventType.internalKey.rawValue }
        assertNoSource(event)
    }

    func test_hybridNetworkRequest_isFetch() throws {
        let (sdk, uploader) = try start(framework: .reactNative(version: "1.0.0"))
        sdk.setNetworkRequestContext(dictionary: [
            Keys.url.rawValue: "https://api.example.com/a",
            Keys.host.rawValue: "api.example.com",
            Keys.method.rawValue: "GET",
            Keys.statusCode.rawValue: 200,
            Keys.duration.rawValue: 10,
            Keys.httpResponseBodySize.rawValue: 0,
            Keys.fragments.rawValue: "/a",
            Keys.schema.rawValue: "https"
        ])
        let event = try awaitEvent(sdk, uploader, "network-request") {
            $0.type == CoralogixEventType.networkRequest.rawValue
        }
        XCTAssertNotNil(event.otelAttributes, "a network request carries the OTLP mirror")
        assertSource(event, .fetch)
    }
}
