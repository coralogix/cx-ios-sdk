//
//  InteractionContextTests.swift
//
//
//  Created by Coralogix Dev Team on 04/08/2024.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class InteractionContextTests: XCTestCase {

    // MARK: - Helpers

    private func makeSpan(tapObject: [String: Any]) -> SpanDataProtocol {
        let now = Date()
        return MockSpanData(
            attributes: [
                Keys.severity.rawValue:    AttributeValue("3"),
                Keys.eventType.rawValue:   AttributeValue("user-interaction"),
                Keys.source.rawValue:      AttributeValue("console"),
                Keys.environment.rawValue: AttributeValue("prod"),
                Keys.tapObject.rawValue:   AttributeValue(Helper.convertDictionayToJsonString(dict: tapObject))
            ],
            startTime: now,
            endTime: now,
            spanId: "span123",
            traceId: "trace123",
            name: "testSpan",
            kind: 1,
            statusCode: ["status": "ok"],
            resources: ["a": AttributeValue("1")]
        )
    }

    // MARK: - InteractionEventName enum

    func testInteractionEventName_rawValues() {
        XCTAssertEqual(InteractionEventName(rawValue: "click"),  .click)
        XCTAssertEqual(InteractionEventName(rawValue: "scroll"), .scroll)
        XCTAssertEqual(InteractionEventName(rawValue: "swipe"),  .swipe)
        XCTAssertNil(InteractionEventName(rawValue: "unknown"))
    }

    // MARK: - ScrollDirection enum

    func testScrollDirection_rawValues() {
        XCTAssertEqual(ScrollDirection(rawValue: "up"),    .up)
        XCTAssertEqual(ScrollDirection(rawValue: "down"),  .down)
        XCTAssertEqual(ScrollDirection(rawValue: "left"),  .left)
        XCTAssertEqual(ScrollDirection(rawValue: "right"), .right)
        XCTAssertNil(ScrollDirection(rawValue: "diagonal"))
    }

    // MARK: - TapDataExtractor.resolveClassName

    /// Private / internal UIKit subclass names must be normalized to their canonical public name.
    func testResolveClassName_privateSubclassNames_mapToCanonical() {
        XCTAssertEqual(TapDataExtractor.resolveClassName("UITableViewCellContentView"), "UITableViewCell")
        XCTAssertEqual(TapDataExtractor.resolveClassName("_UIPageIndicatorView"),       "UIPageIndicatorView")
        XCTAssertEqual(TapDataExtractor.resolveClassName("UITabBarButton"),             "UITabBarButton")
        XCTAssertEqual(TapDataExtractor.resolveClassName("UICollectionViewCell"),       "UICollectionViewCell")
        XCTAssertEqual(TapDataExtractor.resolveClassName("UITableView"),                "UITableView")
    }

    /// Unknown class names must pass through unchanged so element_classes is never silently dropped.
    func testResolveClassName_unknownClass_returnsAsIs() {
        XCTAssertEqual(TapDataExtractor.resolveClassName("UIListContentView"),  "UIListContentView")
        XCTAssertEqual(TapDataExtractor.resolveClassName("SomeThirdPartyView"), "SomeThirdPartyView")
        // A third-party class whose name *contains* a UIKit name mid-string must NOT be misidentified.
        XCTAssertEqual(TapDataExtractor.resolveClassName("SomeSDKUITableViewProxy"), "SomeSDKUITableViewProxy")
        // Module-prefixed names should still resolve correctly.
        XCTAssertEqual(TapDataExtractor.resolveClassName("UIKit.UITableViewCell"), "UITableViewCell")
    }

    // MARK: - Interaction context attributes (x/y)

    /// Tap position (x/y) must appear in interaction_context.attributes so dashboards can use them.
    func testInit_tapEvent_positionAppearsInAttributes() {
        let tapObject: [String: Any] = [
            Keys.eventName.rawValue:      "click",
            Keys.elementClasses.rawValue: "UIButton",
            Keys.targetElement.rawValue:  "UIButton",
            Keys.attributes.rawValue:  [Keys.positionX.rawValue: 100.0,
                                        Keys.positionY.rawValue: 200.0]
        ]
        let context = InteractionContext(otel: makeSpan(tapObject: tapObject))

        XCTAssertNotNil(context.attributes, "attributes must not be nil when position is present")
        XCTAssertNotNil(context.attributes?[Keys.positionX.rawValue], "positionX must be in attributes")
        XCTAssertNotNil(context.attributes?[Keys.positionY.rawValue], "positionY must be in attributes")
    }

    // MARK: - ScrollTracker.direction(from:to:)

    /// Downward finger movement (content scrolls down) must resolve to .down.
    func testScrollTracker_verticalDown_returnsDown() {
        let tracker = ScrollTracker()
        let result = tracker.direction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 150))
        XCTAssertEqual(result, .down)
    }

    /// Upward finger movement (content scrolls up) must resolve to .up.
    func testScrollTracker_verticalUp_returnsUp() {
        let tracker = ScrollTracker()
        let result = tracker.direction(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 102, y: 100))
        XCTAssertEqual(result, .up)
    }

    /// Rightward finger movement must resolve to .right.
    func testScrollTracker_horizontalRight_returnsRight() {
        let tracker = ScrollTracker()
        let result = tracker.direction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 150, y: 102))
        XCTAssertEqual(result, .right)
    }

    /// Leftward finger movement must resolve to .left.
    func testScrollTracker_horizontalLeft_returnsLeft() {
        let tracker = ScrollTracker()
        let result = tracker.direction(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 100, y: 102))
        XCTAssertEqual(result, .left)
    }

    /// Movement below the threshold (small wobble during a tap) must return nil — treated as a tap.
    func testScrollTracker_belowThreshold_returnsNil() {
        let tracker = ScrollTracker()
        let result = tracker.direction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 105, y: 105))
        XCTAssertNil(result, "Movement below threshold must be classified as a tap, not a scroll")
    }

    /// Exactly at the threshold must be treated as a scroll.
    func testScrollTracker_exactThreshold_returnsDirection() {
        let tracker = ScrollTracker()
        let result = tracker.direction(from: CGPoint(x: 0, y: 0),
                                       to: CGPoint(x: 0, y: ScrollTracker.threshold))
        XCTAssertEqual(result, .down)
    }

    // MARK: - safeInnerText — PII rules

    /// UITextField must always return nil regardless of content (user-typed).
    func testSafeInnerText_textField_returnsNil() {
        let tf = UITextField()
        tf.text = "user@example.com"
        XCTAssertNil(TapDataExtractor.safeInnerText(from: tf))
    }

    /// Secure UITextField (password) must also return nil.
    func testSafeInnerText_secureTextField_returnsNil() {
        let tf = UITextField()
        tf.isSecureTextEntry = true
        tf.text = "super-secret"
        XCTAssertNil(TapDataExtractor.safeInnerText(from: tf))
    }

    /// UITextView must always return nil (free-form user content).
    func testSafeInnerText_textView_returnsNil() {
        let tv = UITextView()
        tv.text = "some user note"
        XCTAssertNil(TapDataExtractor.safeInnerText(from: tv))
    }

    /// UISearchBar must always return nil (user search query).
    func testSafeInnerText_searchBar_returnsNil() {
        let sb = UISearchBar()
        sb.text = "search term"
        XCTAssertNil(TapDataExtractor.safeInnerText(from: sb))
    }

    /// UIButton title is developer-authored — must be captured.
    func testSafeInnerText_button_returnsTitle() {
        let btn = UIButton()
        btn.setTitle("Add to Cart", for: .normal)
        XCTAssertEqual(TapDataExtractor.safeInnerText(from: btn), "Add to Cart")
    }

    /// UILabel text is developer-authored — must be captured.
    func testSafeInnerText_label_returnsText() {
        let lbl = UILabel()
        lbl.text = "Section Header"
        XCTAssertEqual(TapDataExtractor.safeInnerText(from: lbl), "Section Header")
    }

    /// UITableViewCell primary text is developer-authored — must be captured.
    func testSafeInnerText_tableViewCell_returnsTextLabel() {
        let cell = UITableViewCell()
        cell.textLabel?.text = "Settings"
        XCTAssertEqual(TapDataExtractor.safeInnerText(from: cell), "Settings")
    }

    /// UISegmentedControl selected segment title is developer-authored — must be captured.
    func testSafeInnerText_segmentedControl_returnsSelectedTitle() {
        let seg = UISegmentedControl(items: ["Day", "Week", "Month"])
        seg.selectedSegmentIndex = 1
        XCTAssertEqual(TapDataExtractor.safeInnerText(from: seg), "Week")
    }

    /// UISegmentedControl with no selection must return nil.
    func testSafeInnerText_segmentedControl_noSelection_returnsNil() {
        let seg = UISegmentedControl(items: ["Day", "Week"])
        seg.selectedSegmentIndex = UISegmentedControl.noSegment
        XCTAssertNil(TapDataExtractor.safeInnerText(from: seg))
    }

    /// accessibilityLabel is the safe fallback for any other view type.
    func testSafeInnerText_genericView_usesAccessibilityLabel() {
        let view = UIView()
        view.accessibilityLabel = "Profile Avatar"
        XCTAssertEqual(TapDataExtractor.safeInnerText(from: view), "Profile Avatar")
    }

    /// A generic UIView with no text and no accessibilityLabel must return nil.
    func testSafeInnerText_genericView_noText_returnsNil() {
        XCTAssertNil(TapDataExtractor.safeInnerText(from: UIView()))
    }

    // MARK: - ScrollTracker.direction — simulates the .cancelled path
    //
    // UIScrollView / UITableView gesture recognisers *cancel* touches instead of ending them.
    // When that happens, processCancelled(touch) uses state.current (last .moved position) to
    // compute the direction. The direction() function below is the same logic — so these tests
    // also validate what processCancelled would return for a typical in-table scroll.

    /// A realistic downward table scroll (finger moves ~120 pts down) must resolve to .down.
    func testScrollTracker_cancelledDownScroll_directionIsDown() {
        let tracker = ScrollTracker()
        let result = tracker.direction(from: CGPoint(x: 190, y: 300), to: CGPoint(x: 192, y: 420))
        XCTAssertEqual(result, .down, "Cancelled downward scroll must resolve to .down")
    }

    /// A realistic upward table scroll must resolve to .up.
    func testScrollTracker_cancelledUpScroll_directionIsUp() {
        let tracker = ScrollTracker()
        let result = tracker.direction(from: CGPoint(x: 190, y: 420), to: CGPoint(x: 192, y: 300))
        XCTAssertEqual(result, .up, "Cancelled upward scroll must resolve to .up")
    }

    /// A small wobble during a tap that gets cancelled must not produce a scroll event.
    func testScrollTracker_cancelledTinyMovement_returnsNil() {
        let tracker = ScrollTracker()
        let result = tracker.direction(from: CGPoint(x: 190, y: 300), to: CGPoint(x: 191, y: 308))
        XCTAssertNil(result, "Cancelled touch with sub-threshold movement must not fire a scroll event")
    }

    // MARK: - ScrollTracker off-main-thread guard

    /// processCancelled called from a background thread must return nil without crashing.
    /// This guards the SDK safety rule: never crash the host app due to threading mistakes.
    func testScrollTracker_processCancelled_offMainThread_returnsNilSafely() {
        let tracker = ScrollTracker()
        let expectation = self.expectation(description: "background thread completed")
        var result: (view: UIView, direction: ScrollDirection)? = (UIView(), .down)

        DispatchQueue.global().async {
            result = tracker.processCancelled(UITouch())
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
        XCTAssertNil(result, "processCancelled off the main thread must return nil, not crash")
    }

    // MARK: - Tap / Click

    /// A standard tap event must populate event_name, element_classes, element_id,
    /// target_element_inner_text, and target_element.
    func testInit_tapEvent_mapsAllFields() {
        let tapObject: [String: Any] = [
            Keys.eventName.rawValue:              "click",
            Keys.elementClasses.rawValue:         "UIButton",
            Keys.elementId.rawValue:              "buy_button",
            Keys.targetElementInnerText.rawValue: "Buy Now",
            Keys.targetElement.rawValue:          "UIButton",
            Keys.attributes.rawValue:              [Keys.text.rawValue: "promo"]
        ]
        let context = InteractionContext(otel: makeSpan(tapObject: tapObject))

        XCTAssertEqual(context.eventName,              .click)
        XCTAssertEqual(context.elementClasses,         "UIButton")
        XCTAssertEqual(context.elementId,              "buy_button")
        XCTAssertEqual(context.targetElementInnerText, "Buy Now")
        XCTAssertNil(context.scrollDirection,          "Tap must not have a scroll direction")
        XCTAssertEqual(context.targetElement,          "UIButton")
        XCTAssertEqual(context.attributes?[Keys.text.rawValue] as? String, "promo")
    }

    /// event_name must default to "click" when the tapObject omits it.
    func testInit_missingEventName_defaultsToClick() {
        let tapObject: [String: Any] = [
            Keys.elementClasses.rawValue: "UITableViewCell",
            Keys.targetElement.rawValue:  "UITableViewCell"
        ]
        let context = InteractionContext(otel: makeSpan(tapObject: tapObject))

        XCTAssertEqual(context.eventName, .click)
    }

    /// Optional fields must be nil when absent from the tapObject.
    func testInit_optionalFieldsAbsent_areNil() {
        let tapObject: [String: Any] = [
            Keys.eventName.rawValue:      "click",
            Keys.elementClasses.rawValue: "UIButton",
            Keys.targetElement.rawValue:  "UIButton"
        ]
        let context = InteractionContext(otel: makeSpan(tapObject: tapObject))

        XCTAssertNil(context.elementId)
        XCTAssertNil(context.targetElementInnerText)
        XCTAssertNil(context.scrollDirection)
        XCTAssertNil(context.attributes)
    }

    // MARK: - Scroll

    /// A scroll event must carry event_name "scroll" and a typed scroll_direction.
    func testInit_scrollEvent_mapsDirectionField() {
        let tapObject: [String: Any] = [
            Keys.eventName.rawValue:       "scroll",
            Keys.elementClasses.rawValue:  "UIScrollView",
            Keys.targetElement.rawValue:   "UIScrollView",
            Keys.scrollDirection.rawValue: ScrollDirection.down.rawValue
        ]
        let context = InteractionContext(otel: makeSpan(tapObject: tapObject))

        XCTAssertEqual(context.eventName,       .scroll)
        XCTAssertEqual(context.elementClasses,  "UIScrollView")
        XCTAssertEqual(context.scrollDirection, .down)
        XCTAssertNil(context.elementId)
        XCTAssertNil(context.targetElementInnerText)
    }

    // MARK: - getDictionary

    /// getDictionary must emit strings and omit nil optional fields.
    func testGetDictionary_emitsStringsAndOmitsNilFields() {
        let tapObject: [String: Any] = [
            Keys.eventName.rawValue:      "click",
            Keys.elementClasses.rawValue: "UIButton",
            Keys.targetElement.rawValue:  "UIButton"
        ]
        let dict = InteractionContext(otel: makeSpan(tapObject: tapObject)).getDictionary()

        XCTAssertEqual(dict[Keys.eventName.rawValue] as? String,      "click")
        XCTAssertEqual(dict[Keys.elementClasses.rawValue] as? String, "UIButton")
        XCTAssertEqual(dict[Keys.targetElement.rawValue] as? String,  "UIButton")
        XCTAssertNil(dict[Keys.elementId.rawValue],              "element_id must be absent when nil")
        XCTAssertNil(dict[Keys.targetElementInnerText.rawValue], "target_element_inner_text must be absent when nil")
        XCTAssertNil(dict[Keys.scrollDirection.rawValue],        "scroll_direction must be absent when nil")
        XCTAssertNil(dict[Keys.attributes.rawValue],             "attributes must be absent when nil")
    }

    /// Vertical scroll: direction must dominate when dy > dx.
    func testInit_scrollEvent_verticalDominates() {
        let tapObject: [String: Any] = [
            Keys.eventName.rawValue:       "scroll",
            Keys.elementClasses.rawValue:  "UITableView",
            Keys.targetElement.rawValue:   "UITableView",
            Keys.scrollDirection.rawValue: "up"
        ]
        let context = InteractionContext(otel: makeSpan(tapObject: tapObject))
        XCTAssertEqual(context.scrollDirection, .up)
    }

    /// getDictionary for a scroll event must include scroll_direction as its rawValue string.
    func testGetDictionary_scrollEvent_includesDirectionRawValue() {
        let tapObject: [String: Any] = [
            Keys.eventName.rawValue:       "scroll",
            Keys.elementClasses.rawValue:  "UITableView",
            Keys.targetElement.rawValue:   "UITableView",
            Keys.scrollDirection.rawValue: ScrollDirection.up.rawValue
        ]
        let dict = InteractionContext(otel: makeSpan(tapObject: tapObject)).getDictionary()

        XCTAssertEqual(dict[Keys.eventName.rawValue] as? String,       "scroll")
        XCTAssertEqual(dict[Keys.scrollDirection.rawValue] as? String, "up")
    }

    /// Any class name — including those not previously in any enum — must be preserved as-is.
    func testInit_unknownElementClass_isPreservedAsString() {
        let tapObject: [String: Any] = [
            Keys.eventName.rawValue:      "click",
            Keys.elementClasses.rawValue: "UIListContentView",
            Keys.targetElement.rawValue:  "UIListContentView"
        ]
        let context = InteractionContext(otel: makeSpan(tapObject: tapObject))

        XCTAssertEqual(context.elementClasses, "UIListContentView",
                       "Any class name must be kept as-is, never silently dropped")
    }

    /// An empty / missing tapObject must produce a context with all nil fields.
    func testInit_emptySpan_producesAllNilContext() {
        let now = Date()
        let emptySpan = MockSpanData(
            attributes: [:],
            startTime: now,
            endTime: now,
            spanId: "s", traceId: "t", name: "n", kind: 1,
            statusCode: [:], resources: [:]
        )
        let context = InteractionContext(otel: emptySpan)

        XCTAssertNil(context.eventName)
        XCTAssertNil(context.elementClasses)
        XCTAssertNil(context.elementId)
        XCTAssertNil(context.targetElementInnerText)
        XCTAssertNil(context.scrollDirection)
        XCTAssertNil(context.targetElement)
        XCTAssertNil(context.attributes)
    }
}
