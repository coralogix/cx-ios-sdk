//
//  SessionReplayTapCaptureTimingTests.swift
//  Coralogix-Rum-Tests
//
//  When a native touch asks session replay for a frame, and how many times, differs by framework.
//  Flutter follows the plugin contract it shares with Android: one frame, requested when the finger
//  lands, and a bridge span that carries no screenshot of its own. React Native and native apps keep
//  requesting the frame once the gesture is classified at finger-up, and stamping it on the span.
//

import XCTest
import UIKit
import CoralogixInternal
@testable import Coralogix

final class SessionReplayTapCaptureTimingTests: XCTestCase {

    private var sessionReplay: MockSessionReplay!
    private var tracer: MockTracer!
    private var rum: CoralogixRum?

    override func setUp() {
        super.setUp()
        sessionReplay = MockSessionReplay()
        tracer = MockTracer()
    }

    override func tearDown() {
        rum?.shutdown()
        rum = nil
        SdkManager.shared.register(sessionReplayInterface: nil)
        sessionReplay = nil
        tracer = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRum(_ framework: SdkFramework) -> CoralogixRum {
        let options = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "test",
            application: "TestApp",
            version: "1.0.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: nil,
            sessionSampleRate: 100,
            instrumentations: [.userActions: true],
            debug: false
        )
        let rum = CoralogixRum(options: options, sdkFramework: framework)
        // Wired up only once init is over, so nothing init does reaches the doubles and every
        // capture and span the tests see comes from the touch or bridge call under test.
        SdkManager.shared.register(sessionReplayInterface: sessionReplay)
        let tracer: MockTracer = self.tracer
        rum.tracerProvider = { tracer }
        self.rum = rum
        return rum
    }

    private let tapLocation = CGPoint(x: 120, y: 340)

    /// The event `cx_sendEvent` posts at `.began`: a click, because nothing is classified yet.
    private func fingerDown() -> Notification {
        Notification(name: .cxRumNotificationTouchBegan,
                     object: TouchEvent(view: UIView(), location: tapLocation, eventType: .click,
                                        touchUptime: ProcessInfo.processInfo.systemUptime))
    }

    /// The event `cx_sendEvent` posts at `.ended` once the touch is classified as a tap.
    private func fingerUpTap() -> Notification {
        Notification(name: .cxRumNotificationUserActions,
                     object: TouchEvent(view: UIView(), location: tapLocation, eventType: .click,
                                        touchUptime: ProcessInfo.processInfo.systemUptime))
    }

    /// A tap as the Flutter and React Native bridges report it through `setUserInteraction`.
    private var bridgeTap: [String: Any] {
        [Keys.eventName.rawValue: InteractionEventName.click.rawValue,
         Keys.targetElement.rawValue: "ElevatedButton",
         Keys.positionX.rawValue: Double(tapLocation.x),
         Keys.positionY.rawValue: Double(tapLocation.y),
         Keys.isMasked.rawValue: false]
    }

    private var userInteractionSpans: [MockSpan] {
        tracer.mockSpanBuilder.startedSpans.filter {
            $0.recordedAttributes[Keys.eventType.rawValue] == .string(CoralogixEventType.userInteraction.rawValue)
        }
    }

    /// The interaction payload the span carries, decoded from its JSON attribute.
    private func tapObject(on span: MockSpan) -> [String: Any]? {
        guard case .string(let json)? = span.recordedAttributes[Keys.tapObject.rawValue],
              let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Flutter: one frame, at finger-down, span-only bridge path

    func testFlutter_fingerDown_requestsOneFrameWithTheTapPositionAndAReservedSlot() throws {
        let rum = makeRum(.flutter(version: "1.0.0"))

        rum.handleTouchBeganNotification(notification: fingerDown())

        XCTAssertEqual(sessionReplay.captureEventCallCount, 1,
                       "Finger-down must request exactly one frame")
        let properties = try XCTUnwrap(sessionReplay.captureEventCalledWith)
        XCTAssertEqual(properties[Keys.eventName.rawValue] as? String, InteractionEventName.click.rawValue)
        XCTAssertEqual(properties[Keys.positionX.rawValue] as? Double, 120,
                       "The marker is painted from the top-level x")
        XCTAssertEqual(properties[Keys.positionY.rawValue] as? Double, 340,
                       "The marker is painted from the top-level y")
        XCTAssertNotNil(properties[Keys.tapTimestamp.rawValue] as? TimeInterval,
                        "Dart judges the tap's age from its own time")
        XCTAssertEqual(properties[Keys.segmentIndex.rawValue] as? Int, 1,
                       "The capture must reserve a screenshot slot, so it is deduplicated like any SDK capture rather than treated as manual")
        XCTAssertEqual(properties[Keys.page.rawValue] as? Int, 0)
        XCTAssertNotNil(properties[Keys.screenshotId.rawValue] as? String)
    }

    func testFlutter_fingerDown_reachesTheCaptureThroughTheNotification() {
        _ = makeRum(.flutter(version: "1.0.0"))

        NotificationCenter.default.post(fingerDown())

        // Other tests may leave instances observing the same notification, so the count is
        // a floor: zero here means the observer was never registered.
        XCTAssertGreaterThanOrEqual(sessionReplay.captureEventCallCount, 1,
                                    "initializeUserActionsInstrumentation must observe the finger-down notification")
    }

    func testFlutter_fingerUpTap_requestsNoFrame() {
        let rum = makeRum(.flutter(version: "1.0.0"))

        rum.handleInteractionNotification(notification: fingerUpTap())

        XCTAssertEqual(sessionReplay.captureEventCallCount, 0,
                       "The frame was requested at finger-down; the classified tap must not request a second one")
        XCTAssertTrue(userInteractionSpans.isEmpty,
                      "A Flutter touch never becomes a native span — the bridge reports it")
    }

    func testFlutter_fingerUpScroll_requestsNoFrame() {
        let rum = makeRum(.flutter(version: "1.0.0"))
        let scroll = Notification(name: .cxRumNotificationUserActions,
                                  object: TouchEvent(view: UIView(), location: tapLocation,
                                                     eventType: .scroll, scrollDirection: .up))

        rum.handleInteractionNotification(notification: scroll)

        XCTAssertEqual(sessionReplay.captureEventCallCount, 0,
                       "Finger-down is the only frame request a Flutter touch produces, whatever it turns into")
    }

    func testFlutter_bridgeTap_endsASpanWithThePayloadAndNoScreenshot() throws {
        let rum = makeRum(.flutter(version: "1.0.0"))

        rum.reportHybridUserInteraction(bridgeTap)

        let spans = userInteractionSpans
        XCTAssertEqual(spans.count, 1, "One bridge tap is one user-interaction span")
        let span = try XCTUnwrap(spans.first)
        XCTAssertTrue(span.didEnd, "The span must close without waiting on a capture")
        let tapObject = try XCTUnwrap(tapObject(on: span))
        XCTAssertEqual(tapObject[Keys.targetElement.rawValue] as? String, "ElevatedButton",
                       "The validated payload must be serialised onto the span")
        XCTAssertEqual(tapObject[Keys.positionX.rawValue] as? Double, 120)
        // The React Native test below proves this same setup does stamp both attributes when
        // the bridge span captures, so their absence here is the Flutter path skipping the capture.
        XCTAssertNil(span.recordedAttributes[Keys.screenshotId.rawValue],
                     "The frame was captured at finger-down; the bridge span carries no screenshot (Android parity)")
        XCTAssertNil(span.recordedAttributes[Keys.page.rawValue])
        XCTAssertEqual(sessionReplay.captureEventCallCount, 0,
                       "The bridge span must not request a frame")
    }

    // MARK: - React Native: unchanged — frame at finger-up, screenshot on the bridge span

    func testReactNative_fingerDown_requestsNoFrame() {
        let rum = makeRum(.reactNative(version: "2.0.0"))

        rum.handleTouchBeganNotification(notification: fingerDown())

        XCTAssertEqual(sessionReplay.captureEventCallCount, 0,
                       "Only Flutter captures at finger-down")
    }

    func testReactNative_fingerUpTap_requestsOneFrame() throws {
        let rum = makeRum(.reactNative(version: "2.0.0"))

        rum.handleInteractionNotification(notification: fingerUpTap())

        XCTAssertEqual(sessionReplay.captureEventCallCount, 1,
                       "React Native still feeds session replay from the classified touch")
        let properties = try XCTUnwrap(sessionReplay.captureEventCalledWith)
        XCTAssertEqual(properties[Keys.positionX.rawValue] as? Double, 120)
        XCTAssertEqual(properties[Keys.segmentIndex.rawValue] as? Int, 1)
        XCTAssertTrue(userInteractionSpans.isEmpty, "The span comes from the bridge, not the touch")
    }

    func testReactNative_bridgeTap_stampsTheFrameItCapturesOntoTheSpan() throws {
        let rum = makeRum(.reactNative(version: "2.0.0"))

        rum.reportHybridUserInteraction(bridgeTap)

        XCTAssertEqual(sessionReplay.captureEventCallCount, 1,
                       "The React Native bridge span still captures its own frame")
        let span = try XCTUnwrap(userInteractionSpans.first)
        XCTAssertEqual(userInteractionSpans.count, 1)
        XCTAssertTrue(span.didEnd)
        XCTAssertNotNil(span.recordedAttributes[Keys.tapObject.rawValue])
        XCTAssertNotNil(span.recordedAttributes[Keys.screenshotId.rawValue],
                        "A shipped frame is stamped on the span")
        XCTAssertNotNil(span.recordedAttributes[Keys.page.rawValue])
    }

    // MARK: - Native: unchanged — no capture at finger-down, span with screenshot at finger-up

    func testNative_fingerDown_requestsNoFrame() {
        let rum = makeRum(.swift)

        rum.handleTouchBeganNotification(notification: fingerDown())

        XCTAssertEqual(sessionReplay.captureEventCallCount, 0,
                       "A native app must not capture before the gesture is classified")
        XCTAssertTrue(userInteractionSpans.isEmpty,
                      "Finger-down must never become a click span — it may still turn into a scroll")
    }

    func testNative_fingerUpTap_emitsASpanWithItsFrame() throws {
        let rum = makeRum(.swift)

        rum.handleInteractionNotification(notification: fingerUpTap())

        XCTAssertEqual(userInteractionSpans.count, 1, "A classified native tap is one span")
        let span = try XCTUnwrap(userInteractionSpans.first)
        XCTAssertTrue(span.didEnd)
        XCTAssertNotNil(span.recordedAttributes[Keys.tapObject.rawValue])
        XCTAssertNotNil(span.recordedAttributes[Keys.screenshotId.rawValue],
                        "The native span keeps stamping the frame it captures")
        XCTAssertEqual(sessionReplay.captureEventCallCount, 1)
    }
}
