//
//  SessionReplayTapCaptureTimingTests.swift
//  Coralogix-Rum-Tests
//
//  The same rule for every framework, as on Android: session replay takes its frame when the
//  finger lands, once per tap, and a user-interaction span — native or bridge-reported — carries
//  the payload and no screenshot. The classified gesture at finger-up captures nothing.
//

import XCTest
import UIKit
import CoralogixInternal
@testable import Coralogix

final class SessionReplayTapCaptureTimingTests: XCTestCase {

    private var sessionReplay: MockSessionReplay!
    private var tracer: MockTracer!
    private var rum: CoralogixRum?

    private let frameworks: [SdkFramework] = [.swift, .reactNative(version: "2.0.0"), .flutter(version: "1.0.0")]
    private let hybrids: [SdkFramework] = [.reactNative(version: "2.0.0"), .flutter(version: "1.0.0")]

    override func tearDown() {
        shutDownRum()
        SdkManager.shared.register(sessionReplayInterface: nil)
        sessionReplay = nil
        tracer = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A fresh SDK instance and fresh doubles for `framework`, replacing any from an earlier loop
    /// iteration so every count starts at zero.
    private func makeRum(_ framework: SdkFramework,
                         shouldSendText: ((UIView, String) -> Bool)? = nil,
                         resolveTargetName: ((UIView) -> String?)? = nil) -> CoralogixRum {
        shutDownRum()
        sessionReplay = MockSessionReplay()
        tracer = MockTracer()
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
            shouldSendText: shouldSendText,
            resolveTargetName: resolveTargetName,
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

    private func shutDownRum() {
        rum?.shutdown()
        rum = nil
    }

    private let tapLocation = CGPoint(x: 120, y: 340)

    /// The event `cx_sendEvent` posts at `.began`: a click, because nothing is classified yet.
    private func fingerDown(on view: UIView = UIView()) -> Notification {
        Notification(name: .cxRumNotificationUserActions,
                     object: TouchEvent(view: view, location: tapLocation, eventType: .click,
                                        touchUptime: ProcessInfo.processInfo.systemUptime, phase: .began))
    }

    /// The event `cx_sendEvent` posts at `.ended` once the touch is classified as a tap.
    private func fingerUpTap(on view: UIView = UIView()) -> Notification {
        Notification(name: .cxRumNotificationUserActions,
                     object: TouchEvent(view: view, location: tapLocation, eventType: .click,
                                        touchUptime: ProcessInfo.processInfo.systemUptime))
    }

    /// The event `cx_sendEvent` posts at `.ended` once the touch is classified as a scroll.
    private func fingerUpScroll() -> Notification {
        Notification(name: .cxRumNotificationUserActions,
                     object: TouchEvent(view: UIView(), location: tapLocation,
                                        eventType: .scroll, scrollDirection: .up))
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

    private func assertSpanOnly(_ span: MockSpan, _ framework: SdkFramework,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(span.didEnd, "\(framework): the span must close without waiting on a capture",
                      file: file, line: line)
        let payload = try XCTUnwrap(tapObject(on: span), "\(framework): the payload must be serialised onto the span",
                                    file: file, line: line)
        XCTAssertEqual(payload[Keys.eventName.rawValue] as? String, InteractionEventName.click.rawValue,
                       file: file, line: line)
        XCTAssertEqual(payload[Keys.positionX.rawValue] as? Double, 120, file: file, line: line)
        // `testScreenshotSpan_isEmittedOnlyWhenAFrameShipped` proves `recordScreenshotForSpan`
        // stamps both attributes on a MockSpan in this same setup, so their absence here is the
        // interaction path never recording a capture on its span.
        XCTAssertNil(span.recordedAttributes[Keys.screenshotId.rawValue],
                     "\(framework): an interaction span carries no screenshot (Android parity)",
                     file: file, line: line)
        XCTAssertNil(span.recordedAttributes[Keys.page.rawValue], file: file, line: line)
    }

    // MARK: - The phase every existing producer reports

    /// Only the `.began` case in `cx_sendEvent` says otherwise, so every tap, scroll and swipe the
    /// swizzles and the SwiftUI recognisers already post keeps being a classified gesture.
    func testTouchEvent_isAClassifiedGestureUnlessTheProducerSaysOtherwise() {
        XCTAssertEqual(TouchEvent(view: UIView(), location: tapLocation, eventType: .click).phase, .ended)
        XCTAssertEqual(TouchEvent(view: UIView(), touch: UITouch(), eventType: .scroll).phase, .ended)
        XCTAssertEqual(TouchEvent(view: UIView(), location: tapLocation, eventType: .click, phase: .began).phase,
                       .began)
    }

    // MARK: - Finger-down: one frame, for every framework

    func testFingerDown_requestsOneFrameWithTheTapPositionAndAReservedSlot_forEveryFramework() throws {
        for framework in frameworks {
            let rum = makeRum(framework)

            rum.handleInteractionNotification(notification: fingerDown())

            XCTAssertEqual(sessionReplay.captureEventCallCount, 1,
                           "\(framework): finger-down must request exactly one frame")
            let properties = try XCTUnwrap(sessionReplay.captureEventCalledWith)
            XCTAssertEqual(properties[Keys.eventName.rawValue] as? String, InteractionEventName.click.rawValue)
            XCTAssertEqual(properties[Keys.positionX.rawValue] as? Double, 120,
                           "\(framework): the marker is painted from the top-level x")
            XCTAssertEqual(properties[Keys.positionY.rawValue] as? Double, 340,
                           "\(framework): the marker is painted from the top-level y")
            XCTAssertNotNil(properties[Keys.tapTimestamp.rawValue] as? TimeInterval,
                            "\(framework): a Flutter bitmap provider judges the tap's age from its own time")
            XCTAssertEqual(properties[Keys.segmentIndex.rawValue] as? Int, 1,
                           "\(framework): the capture must reserve a screenshot slot, so it is deduplicated like any SDK capture rather than treated as manual")
            XCTAssertEqual(properties[Keys.page.rawValue] as? Int, 0)
            XCTAssertNotNil(properties[Keys.screenshotId.rawValue] as? String)
            XCTAssertTrue(userInteractionSpans.isEmpty,
                          "\(framework): finger-down must never become a span — it may still turn into a scroll")
        }
    }

    func testFingerDown_reachesTheCaptureThroughTheNotification() {
        _ = makeRum(.swift)

        NotificationCenter.default.post(fingerDown())

        // Other tests may leave instances observing the same notification, so the count is
        // a floor: zero here means a finger-down never reaches the capture through the observer.
        XCTAssertGreaterThanOrEqual(sessionReplay.captureEventCallCount, 1,
                                    "The user-actions observer must act on a `.began` event")
    }

    // MARK: - Finger-up: no frame, for every framework

    func testFingerUp_requestsNoFrame_forEveryFrameworkAndGesture() {
        for framework in frameworks {
            for gesture in [fingerUpTap(), fingerUpScroll()] {
                let rum = makeRum(framework)

                rum.handleInteractionNotification(notification: gesture)

                XCTAssertEqual(sessionReplay.captureEventCallCount, 0,
                               "\(framework): the frame was requested at finger-down; the classified gesture must not request another")
            }
        }
    }

    func testNative_fingerUpTap_emitsASpanWithNoScreenshot() throws {
        let rum = makeRum(.swift)

        rum.handleInteractionNotification(notification: fingerUpTap())

        XCTAssertEqual(userInteractionSpans.count, 1, "A classified native tap is one span")
        let span = try XCTUnwrap(userInteractionSpans.first)
        try assertSpanOnly(span, .swift)
    }

    func testNative_fingerUpScroll_emitsASpanWithTheDirectionAndNoScreenshot() throws {
        let rum = makeRum(.swift)

        rum.handleInteractionNotification(notification: fingerUpScroll())

        XCTAssertEqual(userInteractionSpans.count, 1, "A classified native scroll is one span")
        let span = try XCTUnwrap(userInteractionSpans.first)
        XCTAssertTrue(span.didEnd)
        let payload = try XCTUnwrap(tapObject(on: span))
        XCTAssertEqual(payload[Keys.eventName.rawValue] as? String, InteractionEventName.scroll.rawValue)
        XCTAssertEqual(payload[Keys.scrollDirection.rawValue] as? String, ScrollDirection.up.rawValue)
        XCTAssertNil(span.recordedAttributes[Keys.screenshotId.rawValue],
                     "A scroll span carries no screenshot either")
        XCTAssertEqual(sessionReplay.captureEventCallCount, 0, "A scroll adds no frame of its own")
    }

    /// Finger-down reads nothing from the view, so the customer's delegates are consulted once
    /// per tap, when the classified gesture becomes a span — never twice, and never for a touch
    /// that goes on to become a scroll.
    func testCustomerDelegates_areConsultedAtFingerUpOnly() {
        var shouldSendTextCalls = 0
        var resolveTargetNameCalls = 0
        let rum = makeRum(.swift,
                          shouldSendText: { _, _ in shouldSendTextCalls += 1; return true },
                          resolveTargetName: { _ in resolveTargetNameCalls += 1; return nil })
        let label = UILabel()
        label.text = "Pay"

        rum.handleInteractionNotification(notification: fingerDown(on: label))

        XCTAssertEqual(sessionReplay.captureEventCallCount, 1, "The finger-down still captures")
        XCTAssertEqual(shouldSendTextCalls, 0, "Nothing is read from the view at finger-down")
        XCTAssertEqual(resolveTargetNameCalls, 0)

        rum.handleInteractionNotification(notification: fingerUpTap(on: label))

        XCTAssertEqual(shouldSendTextCalls, 1, "The classified tap consults the text delegate once")
        XCTAssertEqual(resolveTargetNameCalls, 1, "The classified tap consults the name delegate once")
    }

    func testHybrid_fingerUpTap_emitsNoNativeSpan() {
        for framework in hybrids {
            let rum = makeRum(framework)

            rum.handleInteractionNotification(notification: fingerUpTap())

            XCTAssertTrue(userInteractionSpans.isEmpty,
                          "\(framework): a hybrid touch never becomes a native span — the bridge reports it")
        }
    }

    // MARK: - Bridge: span-only, for both hybrids

    func testHybrid_bridgeTap_endsASpanWithThePayloadAndNoScreenshot_andRequestsNoFrame() throws {
        for framework in hybrids {
            let rum = makeRum(framework)

            rum.reportHybridUserInteraction(bridgeTap)

            let spans = userInteractionSpans
            XCTAssertEqual(spans.count, 1, "\(framework): one bridge tap is one user-interaction span")
            let span = try XCTUnwrap(spans.first)
            try assertSpanOnly(span, framework)
            XCTAssertEqual(tapObject(on: span)?[Keys.targetElement.rawValue] as? String, "ElevatedButton")
            XCTAssertEqual(sessionReplay.captureEventCallCount, 0,
                           "\(framework): the bridge span must not request a frame")
        }
    }
}
