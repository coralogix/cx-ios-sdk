//
//  UserInteractionSpanTests.swift
//  Coralogix-Rum-Tests
//
//  Pins the touch contract of `handleInteractionNotification` for every framework: finger-down opens no span, the classified gesture at finger-up is one interaction span.
//

import XCTest
import UIKit
import CoralogixInternal
@testable import Coralogix

final class UserInteractionSpanTests: XCTestCase {

    private var tracer: MockTracer!
    private var rum: CoralogixRum?

    private let frameworks: [SdkFramework] = [.swift, .reactNative(version: "2.0.0"), .flutter(version: "1.0.0")]
    private let hybrids: [SdkFramework] = [.reactNative(version: "2.0.0"), .flutter(version: "1.0.0")]

    override func tearDown() {
        shutDownRum()
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
        // Wired up only once init is over, so every span the tests see comes from the touch or
        // bridge call under test.
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
                     object: TouchEvent(view: view, location: tapLocation, eventType: .click, phase: .began))
    }

    /// The event `cx_sendEvent` posts at `.ended` once the touch is classified as a tap.
    private func fingerUpTap(on view: UIView = UIView()) -> Notification {
        Notification(name: .cxRumNotificationUserActions,
                     object: TouchEvent(view: view, location: tapLocation, eventType: .click))
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

    private var userInteractionSpans: [MockSpan] { spans(of: .userInteraction) }

    private func spans(of type: CoralogixEventType) -> [MockSpan] {
        tracer.mockSpanBuilder.startedSpans.filter {
            $0.recordedAttributes[Keys.eventType.rawValue] == .string(type.rawValue)
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
        XCTAssertTrue(span.didEnd, "\(framework): the span must close",
                      file: file, line: line)
        let payload = try XCTUnwrap(tapObject(on: span), "\(framework): the payload must be serialised onto the span",
                                    file: file, line: line)
        XCTAssertEqual(payload[Keys.eventName.rawValue] as? String, InteractionEventName.click.rawValue,
                       file: file, line: line)
        XCTAssertEqual(payload[Keys.positionX.rawValue] as? Double, 120, file: file, line: line)
        XCTAssertNil(span.recordedAttributes[Keys.screenshotId.rawValue],
                     "\(framework): an interaction span carries no screenshot",
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

    // MARK: - Finger-down: no span, for every framework

    func testFingerDown_opensNoSpan_forEveryFramework() {
        for framework in frameworks {
            let rum = makeRum(framework)

            rum.handleInteractionNotification(notification: fingerDown())

            XCTAssertTrue(tracer.mockSpanBuilder.startedSpans.isEmpty,
                          "\(framework): finger-down must not start any span")
        }
    }

    // MARK: - Finger-up: one span

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

    func testHybrid_bridgeTap_endsASpanWithThePayloadAndNoScreenshot() throws {
        for framework in hybrids {
            let rum = makeRum(framework)

            rum.reportHybridUserInteraction(bridgeTap)

            let spans = userInteractionSpans
            XCTAssertEqual(spans.count, 1, "\(framework): one bridge tap is one user-interaction span")
            let span = try XCTUnwrap(spans.first)
            try assertSpanOnly(span, framework)
            XCTAssertEqual(tapObject(on: span)?[Keys.targetElement.rawValue] as? String, "ElevatedButton")
        }
    }
}
