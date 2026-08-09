//
//  MaskedInteractionTextTests.swift
//  CoralogixRumTests
//

import XCTest
import UIKit
import CoralogixInternal
@testable import Coralogix

/// Interaction events for anything inside a masked area must report `***` rather than the real
/// text. Masking hides what an element says, not that it was used — the event is still reported.
final class MaskedInteractionTextTests: XCTestCase {

    private func clickEvent(on view: UIView) -> TouchEvent {
        TouchEvent(view: view, location: .zero, eventType: .click, scrollDirection: nil)
    }

    private func innerText(_ data: [String: Any]) -> String? {
        data[Keys.targetElementInnerText.rawValue] as? String
    }

    // MARK: - Inherited masking

    /// The keypad case. Hit-testing resolves the key, which is not itself masked; without
    /// inheritance the digit ships in clear and the PIN is reconstructible from the tap spans.
    func testKeyInsideMaskedContainer_reportsRedactedText() {
        let keypad = UIView()
        keypad.cxMask = true
        let key = UIButton()
        key.setTitle("7", for: .normal)
        keypad.addSubview(key)

        let data = TapDataExtractor.extract(from: clickEvent(on: key))

        XCTAssertEqual(innerText(data), "***",
                       "A key inside a masked keypad must not report its digit")
    }

    /// The same control outside the masked container still reports normally — the redaction must
    /// be caused by the masking, not by the test setup.
    func testUnmaskedTwinOfMaskedKey_reportsItsText() {
        let key = UIButton()
        key.setTitle("7", for: .normal)

        let data = TapDataExtractor.extract(from: clickEvent(on: key))

        XCTAssertEqual(innerText(data), "7",
                       "An identical control outside a masked container must report its text")
    }

    func testDirectlyMaskedView_reportsRedactedText() {
        let label = UILabel()
        label.text = "Account 12345"
        label.cxMask = true

        let data = TapDataExtractor.extract(from: clickEvent(on: label))

        XCTAssertEqual(innerText(data), "***")
    }

    func testMaskingIsInheritedThroughMultipleLevels() {
        let masked = UIView()
        masked.cxMask = true
        let middle = UIView()
        let label = UILabel()
        label.text = "Balance 4,200"
        masked.addSubview(middle)
        middle.addSubview(label)

        let data = TapDataExtractor.extract(from: clickEvent(on: label))

        XCTAssertEqual(innerText(data), "***",
                       "Masking must reach a descendant at any depth")
    }

    // MARK: - Sensitive-field detection

    /// Previously the key was dropped entirely. It is now present and redacted, so iOS and Android
    /// describe a masked tap the same way.
    func testSecureTextField_reportsRedactedText() {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.text = "hunter2"

        let data = TapDataExtractor.extract(from: clickEvent(on: field))

        XCTAssertEqual(innerText(data), "***",
                       "A password field must report *** rather than dropping the key")
    }

    func testCreditCardContentTypeField_reportsRedactedText() {
        let field = UITextField()
        field.textContentType = .creditCardNumber
        field.text = "4111111111111111"

        let data = TapDataExtractor.extract(from: clickEvent(on: field))

        XCTAssertEqual(innerText(data), "***")
    }

    // MARK: - The delegate must never see redacted text

    /// The customer's `shouldSendText` closure is a reporting gate, not an inspection hook. Text
    /// that is already masked must not be handed to it.
    func testShouldSendTextIsNotCalledForAMaskedView() {
        let container = UIView()
        container.cxMask = true
        let button = UIButton()
        button.setTitle("7", for: .normal)
        container.addSubview(button)

        var delegateCalled = false
        let data = TapDataExtractor.extract(from: clickEvent(on: button), shouldSendText: { _, _ in
            delegateCalled = true
            return true
        })

        XCTAssertFalse(delegateCalled,
                       "A masked view's text must not reach the customer's closure")
        XCTAssertEqual(innerText(data), "***",
                       "A delegate returning true must not un-mask a masked view")
    }

    func testShouldSendTextIsNotCalledForASecureField() {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.text = "hunter2"

        var capturedText: String?
        _ = TapDataExtractor.extract(from: clickEvent(on: field), shouldSendText: { _, text in
            capturedText = text
            return true
        })

        XCTAssertNil(capturedText,
                     "A password must never be passed to the customer's closure")
    }

    // MARK: - is_masked_element

    /// The masked boolean the redaction already computes is reported, not discarded — masked
    /// and unmasked taps must be distinguishable without parsing `***`.
    func testMaskedTap_reportsIsMaskedElementTrue() {
        let keypad = UIView()
        keypad.cxMask = true
        let key = UIButton()
        key.setTitle("7", for: .normal)
        keypad.addSubview(key)

        let data = TapDataExtractor.extract(from: clickEvent(on: key))

        XCTAssertEqual(data[Keys.isMaskedElement.rawValue] as? Bool, true)
    }

    func testUnmaskedTap_reportsIsMaskedElementFalse() {
        let key = UIButton()
        key.setTitle("7", for: .normal)

        let data = TapDataExtractor.extract(from: clickEvent(on: key))

        XCTAssertEqual(data[Keys.isMaskedElement.rawValue] as? Bool, false,
                       "The flag must be present and false, not absent")
    }

    /// The flag is not tied to text: a masked view with nothing to say still reports true.
    func testMaskedViewWithNoText_stillReportsFlagTrue() {
        let container = UIView()
        container.cxMask = true
        let stepper = UIStepper()
        container.addSubview(stepper)

        let data = TapDataExtractor.extract(from: clickEvent(on: stepper))

        XCTAssertEqual(data[Keys.isMaskedElement.rawValue] as? Bool, true)
    }

    /// The customer's reporting gate is not session-replay masking: text redacted by
    /// `shouldSendText` alone must not claim the element was masked.
    func testShouldSendTextRejection_redactsText_butFlagStaysFalse() {
        let button = UIButton()
        button.setTitle("Buy Now", for: .normal)

        let data = TapDataExtractor.extract(from: clickEvent(on: button),
                                            shouldSendText: { _, _ in false })

        XCTAssertEqual(innerText(data), "***")
        XCTAssertEqual(data[Keys.isMaskedElement.rawValue] as? Bool, false)
    }

    // MARK: - Frame-geometry masking

    /// The mask rects are the preferred oracle: they cover what the view tree cannot see —
    /// SwiftUI `.cxMask()` overlays and `maskText`/`maskAllImages` matches — so the flag and
    /// the replay's suppressed tap marker resolve from the same geometry and cannot disagree.
    func testTapInsideMaskRect_redactsAndFlagsTrue_evenWhenViewTreeSaysUnmasked() {
        let label = UILabel()
        label.text = "Balance 4,200"
        let event = TouchEvent(view: label, location: CGPoint(x: 50, y: 50),
                               eventType: .click, scrollDirection: nil)

        let data = TapDataExtractor.extract(from: event,
                                            maskRects: [CGRect(x: 0, y: 0, width: 100, height: 100)])

        XCTAssertEqual(innerText(data), "***",
                       "Text the pixels masked must not ship in the clear")
        XCTAssertEqual(data[Keys.isMaskedElement.rawValue] as? Bool, true)
    }

    func testTapOutsideMaskRects_notRedacted_flagFalse() {
        let label = UILabel()
        label.text = "Public caption"
        let event = TouchEvent(view: label, location: CGPoint(x: 200, y: 200),
                               eventType: .click, scrollDirection: nil)

        let data = TapDataExtractor.extract(from: event,
                                            maskRects: [CGRect(x: 0, y: 0, width: 100, height: 100)])

        XCTAssertEqual(innerText(data), "Public caption")
        XCTAssertEqual(data[Keys.isMaskedElement.rawValue] as? Bool, false)
    }

    /// No geometry (nil) must not erase the view-tree answer — a masked subtree still masks.
    func testNilMaskRects_viewTreeOracleStillApplies() {
        let container = UIView()
        container.cxMask = true
        let button = UIButton()
        button.setTitle("7", for: .normal)
        container.addSubview(button)
        let event = TouchEvent(view: button, location: CGPoint(x: 5, y: 5),
                               eventType: .click, scrollDirection: nil)

        let data = TapDataExtractor.extract(from: event, maskRects: nil)

        XCTAssertEqual(innerText(data), "***")
        XCTAssertEqual(data[Keys.isMaskedElement.rawValue] as? Bool, true)
    }

    // MARK: - Absent text stays absent

    /// Redaction applies to text that exists. A view with nothing to say still reports no key,
    /// so `***` continues to mean "there was something here".
    func testMaskedViewWithNoText_reportsNoInnerTextKey() {
        let container = UIView()
        container.cxMask = true
        let stepper = UIStepper()
        container.addSubview(stepper)

        let data = TapDataExtractor.extract(from: clickEvent(on: stepper))

        XCTAssertNil(data[Keys.targetElementInnerText.rawValue],
                     "A masked view with no text must not invent a redacted value")
    }
}
