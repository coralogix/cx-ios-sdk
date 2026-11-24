//
//  RumWithoutReplayTests.swift
//  Coralogix-Rum-Tests
//
//  What RUM keeps doing once the screenshot-based session replay is gone from this SDK.
//
//  Header contract for the implementer: this file creates NO new production symbol and needs
//  none. It drives only entry points that survive the removal:
//    - `CoralogixRum.handleInteractionNotification(notification:)`, `reportHybridUserInteraction(_:)`,
//      `validateHybridInteraction(_:maskRects:)` — tap redaction, native and hybrid.
//    - `UIView.deliberateMaskRects(in:)`, `UIView.cxMask` — the mask geometry the hybrid path reads.
//    - `CoralogixRum.reportError(error:)`, `log(severity:message:)`, `initializeANRInstrumentation()`
//      + `metricsManager.eventReporter`, `trackNavigation(for:)` — error, ANR and navigation spans.
//    - `CoralogixExporter.export(spans:explicitTimeout:)` with `spanUploader` — the wire payload.
//    - `CoralogixRum.getSessionID()`, `getSessionCreationTimestamp()`, `getApplication()`,
//      `getCoralogixDomain()`, `getPublicKey()`, `getProxyUrl()`, `isDebug()`, `isIdle()`,
//      `isSessionSampledIn()` — the session getters, kept as plain public `CoralogixRum` methods
//      with today's behaviour (their `public` is pinned separately by `KeptPublicGettersTests`).
//    - `CoralogixRum.reportError(message:stackTrace:errorType:isCrash:)` — a hybrid live crash,
//      whose span must still be flushed once it ends.
//  Every test here is a GUARD: it passes before the removal and must still pass after it.
//

import XCTest
import UIKit
@testable import Coralogix

final class RumWithoutReplayTests: XCTestCase {

    private var rum: CoralogixRum?
    private var tracer: MockTracer!

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
    }

    override func tearDown() {
        rum?.shutdown()
        rum = nil
        tracer = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRum(_ framework: SdkFramework = .swift,
                         proxyUrl: String? = nil,
                         debug: Bool = false) -> CoralogixRum {
        let options = CoralogixExporterOptions(coralogixDomain: .EU2,
                                               environment: "test",
                                               application: "NoReplayApp",
                                               version: "1.0.0",
                                               publicKey: "no-replay-key",
                                               sessionSampleRate: 100,
                                               instrumentations: [.userActions: true, .errors: true],
                                               proxyUrl: proxyUrl,
                                               debug: debug)
        let rum = CoralogixRum(options: options, sdkFramework: framework)
        let tracer = MockTracer()
        self.tracer = tracer
        rum.tracerProvider = { tracer }
        self.rum = rum
        return rum
    }

    private func spans(of type: CoralogixEventType) -> [MockSpan] {
        tracer.mockSpanBuilder.startedSpans.filter {
            $0.recordedAttributes[Keys.eventType.rawValue] == .string(type.rawValue)
        }
    }

    private func tapObject(on span: MockSpan) -> [String: Any]? {
        guard case .string(let json)? = span.recordedAttributes[Keys.tapObject.rawValue],
              let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func fingerUpTap(on view: UIView) -> Notification {
        Notification(name: .cxRumNotificationUserActions,
                     object: TouchEvent(view: view, location: CGPoint(x: 10, y: 10), eventType: .click))
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        label.text = text
        return label
    }

    /// The one interaction span a native tap on `view` produces, decoded.
    private func nativeTapPayload(on view: UIView, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let rum = makeRum()
        rum.handleInteractionNotification(notification: fingerUpTap(on: view))
        let spans = spans(of: .userInteraction)
        XCTAssertEqual(spans.count, 1, "one tap is one interaction span", file: file, line: line)
        let span = try XCTUnwrap(spans.first, file: file, line: line)
        XCTAssertTrue(span.didEnd, "the interaction span ends", file: file, line: line)
        return try XCTUnwrap(tapObject(on: span), file: file, line: line)
    }

    private func bridgeTap(x: Double, y: Double, text: String, isMasked: Bool? = nil) -> [String: Any] {
        var dict: [String: Any] = [Keys.eventName.rawValue: InteractionEventName.click.rawValue,
                                   Keys.targetElement.rawValue: "Button",
                                   Keys.targetElementInnerText.rawValue: text,
                                   Keys.positionX.rawValue: x,
                                   Keys.positionY.rawValue: y]
        if let isMasked { dict[Keys.isMasked.rawValue] = isMasked }
        return dict
    }

    /// A shown window holding a `cxMask`'d container (0,0 100x100) with an unmasked child label,
    /// and an unmasked label outside it at (150,150).
    private func makeMaskedWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.isHidden = false
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        container.cxMask = true
        container.addSubview(label("1234"))
        let outside = label("public")
        outside.frame = CGRect(x: 150, y: 150, width: 80, height: 20)
        window.addSubview(container)
        window.addSubview(outside)
        return window
    }

    // MARK: - 1. Tap redaction, native path (D7)

    func testNativeTap_onCxMaskedView_isRedactedInTheInteractionSpan() throws {
        let view = label("4111 1111")
        view.cxMask = true

        let payload = try nativeTapPayload(on: view)

        XCTAssertEqual(payload[Keys.targetElementInnerText.rawValue] as? String, Keys.maskedInnerText.rawValue)
        XCTAssertEqual(payload[Keys.isMaskedElement.rawValue] as? Bool, true)
    }

    func testNativeTap_insideMaskedSubtree_isRedactedInTheInteractionSpan() throws {
        let container = UIView()
        container.cxMask = true
        let child = label("4111 1111")
        container.addSubview(child)

        let payload = try nativeTapPayload(on: child)

        XCTAssertEqual(payload[Keys.targetElementInnerText.rawValue] as? String, Keys.maskedInnerText.rawValue)
        XCTAssertEqual(payload[Keys.isMaskedElement.rawValue] as? Bool, true)
    }

    /// Control: the same tap on an unmasked view ships its text, so the two above are not vacuous.
    func testNativeTap_onUnmaskedView_keepsItsText() throws {
        let payload = try nativeTapPayload(on: label("Pay"))

        XCTAssertEqual(payload[Keys.targetElementInnerText.rawValue] as? String, "Pay")
        XCTAssertEqual(payload[Keys.isMaskedElement.rawValue] as? Bool, false)
    }

    // MARK: - 1. Tap redaction, hybrid path (D7)

    /// The geometry the hybrid path resolves (`deliberateMaskRects`) still finds a `cxMask`'d view
    /// and a view inside a masked subtree, and the bridge payload is redacted against it.
    func testHybridTap_onCxMaskedGeometry_isRedacted_andAViewInsideTheMaskedSubtreeToo() throws {
        let rum = makeRum(.reactNative(version: "2.0.0"))
        let window = makeMaskedWindow()
        let rects = try XCTUnwrap(UIView.deliberateMaskRects(in: [window]))

        let onContainer = try XCTUnwrap(rum.validateHybridInteraction(bridgeTap(x: 90, y: 90, text: "9"), maskRects: rects))
        XCTAssertEqual(onContainer[Keys.targetElementInnerText.rawValue] as? String, Keys.maskedInnerText.rawValue)
        XCTAssertEqual(onContainer[Keys.isMaskedElement.rawValue] as? Bool, true)

        // The child label sits at (0,0 80x20) inside the masked container.
        let onChild = try XCTUnwrap(rum.validateHybridInteraction(bridgeTap(x: 10, y: 10, text: "1234"), maskRects: rects))
        XCTAssertEqual(onChild[Keys.targetElementInnerText.rawValue] as? String, Keys.maskedInnerText.rawValue)
        XCTAssertEqual(onChild[Keys.isMaskedElement.rawValue] as? Bool, true)

        let outside = try XCTUnwrap(rum.validateHybridInteraction(bridgeTap(x: 160, y: 160, text: "public"), maskRects: rects))
        XCTAssertEqual(outside[Keys.targetElementInnerText.rawValue] as? String, "public",
                       "control: a tap outside every masked region keeps its text")
        XCTAssertEqual(outside[Keys.isMaskedElement.rawValue] as? Bool, false)
    }

    /// End to end through the bridge entry point: the span the hybrid reports carries the redaction.
    func testHybridTap_maskedVerdict_isRedactedInTheInteractionSpan() throws {
        let rum = makeRum(.flutter(version: "1.0.0"))

        rum.reportHybridUserInteraction(bridgeTap(x: 10, y: 10, text: "4111", isMasked: true))
        rum.reportHybridUserInteraction(bridgeTap(x: 10, y: 10, text: "Pay", isMasked: false))

        let payloads = try spans(of: .userInteraction).map { span -> [String: Any] in
            XCTAssertTrue(span.didEnd)
            return try XCTUnwrap(tapObject(on: span))
        }
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads.first?[Keys.targetElementInnerText.rawValue] as? String, Keys.maskedInnerText.rawValue)
        XCTAssertEqual(payloads.first?[Keys.isMaskedElement.rawValue] as? Bool, true)
        XCTAssertEqual(payloads.last?[Keys.targetElementInnerText.rawValue] as? String, "Pay")
        XCTAssertEqual(payloads.last?[Keys.isMaskedElement.rawValue] as? Bool, false)
    }

    // MARK: - 2. Error, ANR and navigation spans end with no screenshot (D5)

    private func assertEndedWithoutScreenshot(_ spans: [MockSpan], _ what: String,
                                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(spans.count, 1, "\(what): one span", file: file, line: line)
        guard let span = spans.first else { return }
        XCTAssertTrue(span.didEnd, "\(what): the span ends with no replay present", file: file, line: line)
        for key in [Keys.screenshotId.rawValue, "page", Keys.segmentIndex.rawValue] {
            XCTAssertNil(span.recordedAttributes[key],
                         "\(what): carries no \(key)", file: file, line: line)
        }
    }

    func testReportedNSError_endsWithNoScreenshotAttributes() {
        let rum = makeRum()

        rum.reportError(error: NSError(domain: "no.replay", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"]))

        assertEndedWithoutScreenshot(spans(of: .error), "reportError")
        XCTAssertEqual(spans(of: .error).first?.recordedAttributes[Keys.domain.rawValue], .string("no.replay"),
                       "the error still reports its own attributes")
    }

    func testErrorLog_endsWithNoScreenshotAttributes() {
        let rum = makeRum()

        rum.log(severity: .error, message: "bad", data: nil)

        assertEndedWithoutScreenshot(spans(of: .log), "error-severity log")
    }

    func testANR_endsWithNoScreenshotAttributes() throws {
        let rum = makeRum()
        rum.initializeANRInstrumentation()
        let reporter = try XCTUnwrap(rum.metricsManager.eventReporter)

        reporter.report(ANRErrorEvent())

        assertEndedWithoutScreenshot(spans(of: .error), "ANR")
    }

    func testAppearNavigation_endsWithNoScreenshotAttributes() {
        let rum = makeRum()

        rum.trackNavigation(for: CXView(state: .notifyOnAppear, name: "no-replay-screen-\(UUID().uuidString)"))

        assertEndedWithoutScreenshot(spans(of: .navigation), "navigation")
    }

    /// A live crash is force-flushed once its span ends, rather than waiting out the batch
    /// processor's schedule delay — the process may be about to die.
    func testHybridLiveCrash_isFlushedImmediately_notHeldForTheBatchDelay() throws {
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []),
                               sdkFramework: .flutter(version: "1.0.0"))
        self.rum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = CapturingSpanUploader()
        exporter.spanUploader = uploader
        XCTAssertGreaterThan(Double(Global.BatchSpan.scheduleDelay.rawValue), 1,
                             "the 1 s window below only proves a flush while the batch delay is longer")

        rum.reportError(message: "live-crash", stackTrace: [], errorType: "Error", isCrash: true)

        let isCrash: ([String: Any]) -> Bool = {
            (($0[Keys.errorContext.rawValue] as? [String: Any])?[Keys.isCrash.rawValue] as? Bool) == true
        }
        let deadline = Date().addingTimeInterval(1)
        while !uploader.cxRumPayloads().contains(where: isCrash) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(uploader.cxRumPayloads().contains(where: isCrash),
                      "the crash must be uploaded within 1 s, well inside the batch schedule delay")
    }

    // MARK: - 3 + 4. Wire payload: screenshot_context kept (D4), hasRecording false (D6)

    private func exportAndCapture(_ spans: [SpanData]) throws -> [[String: Any]] {
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        self.rum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = CapturingSpanUploader()
        exporter.spanUploader = uploader
        _ = exporter.export(spans: spans, explicitTimeout: nil)
        return uploader.cxRumPayloads()
    }

    private func eventType(_ cxRum: [String: Any]) -> String? {
        (cxRum[Keys.eventContext.rawValue] as? [String: Any])?[Keys.type.rawValue] as? String
    }

    func testScreenshotEvent_stillEncodesScreenshotContext() throws {
        let before = Date().timeIntervalSince1970
        let span = makeSamplingSpan(eventType: .screenshot, extraAttributes: [
            Keys.screenshotId.rawValue: AttributeValue("shot-1"),
            "page": AttributeValue("3"), // a stored attribute, no longer sent
            Keys.isManual.rawValue: AttributeValue("true")
        ])

        let payloads = try exportAndCapture([span])

        let cxRum = try XCTUnwrap(payloads.first { eventType($0) == CoralogixEventType.screenshot.rawValue },
                                  "a screenshot event is still exported")
        let context = try XCTUnwrap(cxRum[Keys.screenshotContext.rawValue] as? [String: Any],
                                    "screenshot_context is still encoded")
        XCTAssertEqual(context[Keys.screenshotId.rawValue] as? String, "shot-1")
        XCTAssertNil(context["page"], "no page is sent")
        XCTAssertEqual(context[Keys.isManual.rawValue] as? Bool, true)
        let segment = try XCTUnwrap(context[Keys.segmentTimestamp.rawValue] as? Int, "segment timestamp in ms")
        XCTAssertEqual(Double(segment) / 1000, before, accuracy: 5, "the span's start time, in milliseconds")
    }

    /// Control for the above: an event with no screenshot id carries no screenshot_context.
    func testEventWithoutScreenshotId_carriesNoScreenshotContext() throws {
        let payloads = try exportAndCapture([makeSamplingSpan(eventType: .error)])

        let cxRum = try XCTUnwrap(payloads.first { eventType($0) == CoralogixEventType.error.rawValue })
        XCTAssertNil(cxRum[Keys.screenshotContext.rawValue])
    }

    func testHasRecording_isFalseOnTheWire_withNoReplay() throws {
        let payloads = try exportAndCapture([makeSamplingSpan(eventType: .error)])

        XCTAssertEqual(rum?.sessionManager?.hasRecording, false)
        XCTAssertEqual(rum?.sessionManager?.doesSessionHasRecording(), false)
        let cxRum = try XCTUnwrap(payloads.first { eventType($0) == CoralogixEventType.error.rawValue })
        let session = try XCTUnwrap(cxRum[Keys.sessionContext.rawValue] as? [String: Any])
        XCTAssertEqual(session[Keys.hasRecording.rawValue] as? Bool, false)
    }

    // MARK: - 5. Kept session getters (D2)

    func testKeptGetters_returnWhatTheyDidBefore() throws {
        let rum = makeRum(proxyUrl: "https://proxy.example.test", debug: true)
        let sessionManager = try XCTUnwrap(rum.sessionManager)
        let metadata = try XCTUnwrap(sessionManager.getSessionMetadata())

        XCTAssertFalse(rum.getSessionID().isEmpty)
        XCTAssertEqual(rum.getSessionID(), metadata.sessionId)
        XCTAssertEqual(rum.getSessionCreationTimestamp(), metadata.sessionCreationDate)
        XCTAssertGreaterThan(rum.getSessionCreationTimestamp(), 0)
        XCTAssertEqual(rum.getApplication(), "NoReplayApp")
        XCTAssertEqual(rum.getCoralogixDomain(), CoralogixDomain.EU2.rawValue)
        XCTAssertEqual(rum.getPublicKey(), "no-replay-key")
        XCTAssertEqual(rum.getProxyUrl(), "https://proxy.example.test")
        XCTAssertTrue(rum.isDebug())
        XCTAssertEqual(rum.isIdle(), sessionManager.isIdle)
        XCTAssertFalse(rum.isIdle(), "a just-started session is not idle")
        XCTAssertTrue(rum.isSessionSampledIn(), "sample rate 100 samples the session in")
    }

    func testIsIdle_isTrue_afterFifteenMinutesWithoutActivity() throws {
        let rum = makeRum()
        let sessionManager = try XCTUnwrap(rum.coralogixExporter?.getSessionManager())

        sessionManager.lastActivity = Date().addingTimeInterval(-16 * 60)

        XCTAssertTrue(rum.isIdle())
    }

    func testKeptGetters_defaults_whenUnset() {
        let rum = makeRum()

        XCTAssertEqual(rum.getProxyUrl(), "")
        XCTAssertFalse(rum.isDebug())
    }

    func testIsSessionSampledIn_isFalse_forASampledOutSession() {
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 0, exclude: []))
        self.rum = rum

        XCTAssertFalse(rum.isSessionSampledIn())
    }
}
